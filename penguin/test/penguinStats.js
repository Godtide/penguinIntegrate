const hre = require("hardhat");
const { ethers, network } = require("hardhat");

const setupSigners = async () => {

    
const devAddress = "0x033489768527c7915f35bceb4fe084dd5aecf74b" ;
const nestAddress = "0xe9476e16fe488b90ada9ab5c7c2ada81014ba9ee";
const nestAllocatorAddress = "0x033489768527c7915f35bceb4fe084dd5aecf74b";
const performanceFeeAddress ="0x0043aaaaf96dcf7ecff8ac4908a05663f806adaf";


  await network.provider.send('hardhat_impersonateAccount', [devAddress]);
  await network.provider.send('hardhat_impersonateAccount', [nestAddress]);
  await network.provider.send('hardhat_impersonateAccount', [nestAllocatorAddress]);
  await network.provider.send('hardhat_impersonateAccount', [performanceFeeAddress]);



  let devSigner = ethers.provider.getSigner(devAddress);
  let nestSigner = ethers.provider.getSigner(nestAddress);
  let nestAllocatorSigner = ethers.provider.getSigner(nestAllocatorAddress);
  let performanceFeeAddressSigner = ethers.provider.getSigner(performanceFeeAddress);

  
  await network.provider.send("hardhat_setBalance", [devSigner._address,"0x10000000000000000000000",]);
  await network.provider.send("hardhat_setBalance", [nestSigner._address,"0x10000000000000000000000",]);
  await network.provider.send("hardhat_setBalance", [nestAllocatorSigner._address,"0x10000000000000000000000",]);
  await network.provider.send("hardhat_setBalance", [performanceFeeAddressSigner._address,"0x10000000000000000000000",]);


  return [devSigner,nestSigner,nestAllocatorSigner,performanceFeeAddressSigner];
};

// const poolTokenAddr = "0xbA09679Ab223C6bdaf44D45Ba2d7279959289AB0";
// const rewarderAddr = "0x0000000000000000000000000000000000000000";
// const pefiAddr = "0xe896cdeaac9615145c0ca09c8cd5c25bced6384c";



module.exports = {
  setupSigners,
  // poolTokenAddr,
  // rewarderAddr,
  // pefiAddr
};