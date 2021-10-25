/* eslint-disable no-undef */
const { ethers, network } = require("hardhat");
const chai = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");
const {increaseTime, overwriteTokenAmount, increaseBlock, toGwei, fromWei} = require("../../../../test/utils/helpers");
const { expect } = chai;
const {setupSigners, poolTokenAddr, rewarderAddr, pefiAddr} = require("./penguinStats.js");


const doPenguinLPStrategyTest = (startTime= "1634614064", 
               pid="14",
               withUpdate="true",
               txnAmt="25000000000000000000000") => {


    const walletAddr = process.env.WALLET_ADDR;
    let depositTokenContract;
    let iglooMasterContract;

    let devSigner, nestSigner, nestAllocatorSigner, performanceFeeAddressSigner;
    txnAmt = _txnAmt ? _txnAmt : "25000000000000000000000";
    const slot = _slot ? _slot : 0;

    describe("LP Strategy tests for: penguin", async () => {

        before( async () => {
             await network.provider.send('hardhat_impersonateAccount', [walletAddr]);
            walletSigner = ethers.provider.getSigner(walletAddr);
            [ devSigner, 
              nestSigner, 
              nestAllocatorSigner,
              performanceFeeAddressSigner,
            ] = await setupSigners();
            slot = 1;
            await overwriteTokenAmount(poolTokenAddr,walletAddr,txnAmt,slot);

            depositTokenContract = await ethers.getContractAt("ERC20",poolTokenAddr,walletSigner);

           
            const strategyPefiBaseFactory = await ethers.getContractFactory(StrategyPefiUsdcPgnl);
            strategyPefiBaseContract = await strategyPefiBaseFactory.
            deploy(
                 pid
                );


            const iglooMasterFactory = await ethers.getContractFactory(IglooMaster);
            iglooMasterContract = await iglooMasterFactory.deploy(
                pefiAddr, 
                startTime,
                devSigner.address,
                nestSigner.address,
                nestAllocatorSigner.address,
                performanceFeeAddressSigner.address);
                await
          iglooMasterContract.connect(walletSigner).modifyApprovedContracts (
         strategyPefiBaseContract.address,
         withUpdate);
           });

        it("strategy should be able to deposit", async () =>{

          
            let initialBal = await  depositTokenContract.balanceOf(address(this));
            await strategyPefiBaseContract.connect(iglooMasterContract.address).deposit(20 ** 18);
            let finalBal = await  depositTokenContract.balanceOf(address(this));
            expect(finalBal).to.be.gt(initialBal);
        });
        it("strategy should be able to withdraw", async () =>{
            let initialBal = await  depositTokenContract.balanceOf(address(this));
            await strategyPefiBaseContract.connect(iglooMasterContract.address).withdraw(10 ** 18);
            let finalBal = await  depositTokenContract.balanceOf(address(this));
            expect(finalBal).to.be.lt(initialBal);
        });
    });
};

module.exports = {doPenguinLPStrategyTest};