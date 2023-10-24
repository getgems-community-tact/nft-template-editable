import {toNano, beginCell, Address, Cell} from "ton";
import { Blockchain, SandboxContract, TreasuryContract } from "@ton-community/sandbox";
import "@ton-community/test-utils";

import { NftCollection } from "../wrappers/NftCollection";
import {NftItem} from "../build/NftItem/tact_NftItem";

describe("nftCollection", () => {
    const OFFCHAIN_CONTENT_PREFIX = 0x01;
    const string_first = "https://s.getgems.io/nft-staging/c/628f6ab8077060a7a8d52d63/";
    let newContent = beginCell().storeInt(OFFCHAIN_CONTENT_PREFIX, 8).storeStringRefTail(string_first).endCell();

    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let collection: SandboxContract<NftCollection>;
    let nft: SandboxContract<NftItem>;
    let user: SandboxContract<TreasuryContract>;

    beforeAll(async () => {
        blockchain = await Blockchain.create();
        deployer = await blockchain.treasury("deployer");
        user = await blockchain.treasury("user");

        collection = blockchain.openContract(
            await NftCollection.fromInit(deployer.address, newContent, {
                $$type: "RoyaltyParams",
                numerator: 350n, // 350n = 35%
                denominator: 1000n,
                destination: deployer.address,
            })
        );

        const deploy_result = await collection.send(deployer.getSender(), { value: toNano(1) }, "Mint");
        expect(deploy_result.transactions).toHaveTransaction({
            from: deployer.address,
            to: collection.address,
            deploy: true,
            success: true,
        });
    });

    it("Test", async () => {
        console.log("Next IndexID: " + (await collection.getGetCollectionData()).next_item_index);
        console.log("Collection Address: " + collection.address);
    });

    it("should deploy correctly", async () => {
        const deploy_result = await collection.send(deployer.getSender(),
            {
                value: toNano(1)
            }, "Mint"); // Send Mint Transaction
        
        expect(deploy_result.transactions).toHaveTransaction({
            from: deployer.address,
            to: collection.address,
            success: true,
        });

        // Check getters
        expect((await collection.getRoyaltyParams()).numerator).toEqual(350n);

        console.log("next_item_index: " + (await collection.getGetCollectionData()).next_item_index);
    });

    it("should mint correctly", async () => {
        const result = await collection.send(deployer.getSender(), {
            value: toNano(1)
        }, "Mint");

        const nftAddress = new Address(0, Buffer.from(result.transactions[2].address.toString(16), 'hex'));
        expect(result.transactions).toHaveTransaction({
            from: collection.address,
            to: nftAddress,
            deploy: true,
            success: true
        });
        nft = blockchain.openContract(NftItem.fromAddress(nftAddress));
        let data = await nft.getGetNftData();
        expect(data.owner.toString()).toStrictEqual(deployer.address.toString());
        expect(data.collection_address.toString()).toStrictEqual(collection.address.toString());
        expect(data.index).toStrictEqual(2n);
    });

    it("should transfer", async () => {
       const result = await nft.send(deployer.getSender(), {
           value: toNano('0.2')
       },
       {
           $$type: 'Transfer',
           query_id: 0n,
           new_owner: user.address,
           response_destination: user.address,
           custom_payload: null,
           forward_amount: 0n,
           forward_payload: Cell.EMPTY
       }
       );
       expect(result.transactions).toHaveTransaction({
           from: deployer.address,
           to: nft.address,
           success: true
       });
       expect(result.transactions).toHaveTransaction({
           from: nft.address,
           to: user.address,
           success: true
       });
       expect((await nft.getGetNftData()).owner.toString()).toStrictEqual(user.address.toString());
    });

    it('should transfer editorship', async () => {
        await nft.send(deployer.getSender(), {
            value: toNano('0.2')
        },
        {
            $$type: 'TransferEditorship',
            query_id: 0n,
            new_editor: user.address,
            response_destination: user.address,
            forward_amount: 0n,
            forward_payload: Cell.EMPTY
        }
        );
        expect((await nft.getGetNftData()).editor.toString()).toStrictEqual(user.address.toString());
    });

    it('should edit metadata', async () => {
        const newContent = beginCell().storeStringTail('Spite').endCell();
        const result = await nft.send(user.getSender(), {
            value: toNano('0.2')
        },
        {
            $$type: 'UpdateNftContent',
            query_id: 0n,
            new_content: newContent
        }
        );
        expect(result.transactions).toHaveTransaction({
                from: user.address,
                to: nft.address,
                success: true
        });
        const content = beginCell()
            .storeStringTail('Spite') // collection data
            .storeStringTail('2') // index
            .storeStringTail('.json')
            .endCell();
        
        expect((await nft.getGetNftData()).individual_content.hash().toString('hex'))
            .toStrictEqual(content.hash().toString('hex'));
    });
});