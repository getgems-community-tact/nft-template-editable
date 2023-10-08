import "./imports/globals";
import "./imports/messages";

struct GetNftData { 
    is_initialized: Bool;
    index: Int as uint32;
    collection_address: Address; 
    owner: Address;
    individual_content: Cell;
    editor: Address;
}

contract NftItem {
    collection_address: Address;
    item_index: Int as uint32; 
    owner: Address;
    individual_content: Cell;
    editor: Address;
    is_initialized: Bool;

    init(collection_address: Address, item_index: Int, owner: Address, individual_content: Cell, editor: Address){
        self.collection_address = collection_address;
        self.item_index = item_index;
        self.owner = collection_address;
        self.individual_content = individual_content;
        self.editor = editor;
        self.is_initialized = false;
    }

    receive(msg: Transfer){
        let ctx: Context = context();
    
        let msgValue: Int = ctx.value; // Check the gasCost for storage
        let tonBalanceBeforeMsg: Int = myBalance() - msgValue;
        let storageFee: Int = minTonsForStorage - min(tonBalanceBeforeMsg, minTonsForStorage);
        msgValue = msgValue - (storageFee + gasConsumption);

        // Only Owner of the this NFT Item can transfer it.
        require(ctx.sender == self.owner, "access denied");

        require(msgValue > 0, "invalid amount");

        if (self.is_initialized == false) {  // Initial Transfer, aka the "Minting" of the NFT
            self.is_initialized = true;
            self.owner = msg.new_owner;
            send(SendParameters{
                to: msg.response_destination,
                value: 0,
                mode:  SendIgnoreErrors + SendRemainingValue,
                body: Excesses { query_id: msg.query_id }.toCell() //0xd53276db
            });
        } else {
            self.owner = msg.new_owner; // change current owner to the new_owner
            if (msg.forward_amount > 0) {
                send(SendParameters{
                    to: msg.new_owner,
                    value: msg.forward_amount,
                    mode: SendIgnoreErrors, 
                    bounce: false,
                    body: OwnershipAssigned{
                        query_id: msg.query_id,
                        prev_owner: ctx.sender,
                        forward_payload: msg.forward_payload
                    }.toCell()
                }); 
            }
            msgValue = msgValue - ctx.readForwardFee(); 
            if (msg.response_destination != null) { 
                send(SendParameters{ 
                    to: msg.response_destination,
                    value: msgValue - msg.forward_amount,
                    mode: SendPayGasSeparately,
                    body: Excesses { query_id: msg.query_id }.toCell() // 0xd53276db
                });
            } 
        }
    }

    receive(msg: GetStaticData){ 
        let ctx: Context = context();
        send(SendParameters {
            to: ctx.sender,
            value: 0,
            mode: 64,  // (return msg amount except gas fees) 
            bounce: true,
            body: ReportStaticData{
                query_id: msg.query_id,
                index_id: self.item_index,
                collection: self.collection_address
            }.toCell()
        });
    }

    receive(msg: TransferEditorship){
        let ctx: Context = context();
    
        let msgValue: Int = ctx.value; // Check the gasCost for storage
        let tonBalanceBeforeMsg: Int = myBalance() - msgValue;
        let storageFee: Int = minTonsForStorage - min(tonBalanceBeforeMsg, minTonsForStorage);
        msgValue = msgValue - (storageFee + gasConsumption);

        // Only Editor of the this NFT Item can transfer editorship.
        require(ctx.sender == self.editor, "access denied");
        require(msgValue > 0, "invalid amount");

        self.editor = msg.new_editor; // change current editor to the new_editor
        if (msg.forward_amount > 0) {
            send(SendParameters{
                to: msg.new_editor,
                value: msg.forward_amount,
                mode: SendIgnoreErrors, 
                bounce: false,
                body: EditorshipAssigned{
                    query_id: msg.query_id,
                    prev_editor: self.editor,
                    forward_payload: msg.forward_payload
                }.toCell()
            }); 
        }
        msgValue = msgValue - ctx.readForwardFee(); 
        if (msg.response_destination != null) { 
            send(SendParameters{ 
                to: msg.response_destination,
                value: msgValue - msg.forward_amount,
                mode: SendPayGasSeparately,
                body: Excesses { query_id: msg.query_id }.toCell() // 0xd53276db
            });
        } 
    }

    receive(msg: UpdateNftContent) {
        let ctx: Context = context();
        
        // Only Editor of the this NFT can edit it.
        require(ctx.sender == self.editor, "access denied");

        self.individual_content = msg.new_content;
    }

    // --------- Get Function  --------- //
    get fun get_nft_data(): GetNftData {
        let b: StringBuilder = beginString();
        let collectionData: String = self.individual_content.asSlice().asString();
        b.append(collectionData);
        b.append(self.item_index.toString());
        b.append(".json");

        return GetNftData {
            is_initialized: self.is_initialized, 
            index: self.item_index, 
            collection_address: self.collection_address, 
            owner: self.owner,
            individual_content: b.toCell(),
            editor: self.editor
        };
    }
}
