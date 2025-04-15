import {ZK_SYNC_NETWORKS} from '../../utils/zkSync';
import {time} from '@nomicfoundation/hardhat-network-helpers';
import hre from 'hardhat';

async function zkSyncLatest(): Promise<number> {
  const provider = hre.ethers.provider; // Get the network provider
  const latestBlock = await provider.getBlock('latest'); // Query the latest block
  const timestamp = latestBlock.timestamp; // the timestamp of the latest block
  return timestamp + 1; // Return the timestamp + 1 since async takes 1 sec with zk-node we are using (npx hardhat node-zksync --config hardhat-zksync.config.ts)
}

// Check if the current network is zkSync
if (ZK_SYNC_NETWORKS.includes(hre.network.name)) {
  // Override the `time.latest` getter
  Object.defineProperty(time, 'latest', {
    value: zkSyncLatest,
    writable: true,
    configurable: true,
  });
}
