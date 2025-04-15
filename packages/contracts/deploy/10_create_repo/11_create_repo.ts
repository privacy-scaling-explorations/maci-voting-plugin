import {
  PLUGIN_REPO_ENS_SUBDOMAIN_NAME,
  PLUGIN_REPO_PROXY_NAME,
} from '../../plugin-settings';
import {
  findPluginRepo,
  getProductionNetworkName,
  pluginEnsDomain,
  getPluginRepoFactory,
  frameworkSupportsENS,
} from '../../utils/helpers';
import {findEventTopicLog} from '@aragon/osx-commons-sdk';
import {
  PluginRepoRegistryEvents,
  PluginRepoRegistry__factory,
  PluginRepo__factory,
} from '@aragon/osx-ethers';
import {DeployFunction} from 'hardhat-deploy/types';
import {HardhatRuntimeEnvironment} from 'hardhat/types';
import path from 'path';

/**
 * Creates a plugin repo under Aragon's ENS base domain with subdomain requested in the `./plugin-settings.ts` file.
 * @param {HardhatRuntimeEnvironment} hre
 */
const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  console.log(`Creating plugin repo through Aragon's 'PluginRepoFactory'...`);

  const [deployer] = await hre.ethers.getSigners();

  // Get the Aragon `PluginRepoFactory`
  const pluginRepoFactory = await getPluginRepoFactory(hre);

  // if the framework supports ENS, use the subdomain from the `./plugin-settings.ts` file
  // otherwise, use an empty string
  const supportsENS = await frameworkSupportsENS(pluginRepoFactory);
  const subdomain = supportsENS ? PLUGIN_REPO_ENS_SUBDOMAIN_NAME : '';

  // Create the `PluginRepo` through the Aragon `PluginRepoFactory`
  const tx = await pluginRepoFactory.createPluginRepo(
    subdomain,
    deployer.address
  );

  // Get the PluginRepo address and deployment block number from the txn and event therein
  const eventLog =
    findEventTopicLog<PluginRepoRegistryEvents.PluginRepoRegisteredEvent>(
      await tx.wait(),
      PluginRepoRegistry__factory.createInterface(),
      'PluginRepoRegistered'
    );

  const pluginRepo = PluginRepo__factory.connect(
    eventLog.args.pluginRepo,
    deployer
  );

  // Save the plugin repo deployment
  await hre.deployments.save(PLUGIN_REPO_PROXY_NAME, {
    abi: PluginRepo__factory.abi,
    address: pluginRepo.address,
    receipt: await tx.wait(),
    transactionHash: tx.hash,
  });

  console.log(
    `PluginRepo ${
      supportsENS ? 'with ens:' + pluginEnsDomain(hre) : 'without ens'
    }  deployed at '${pluginRepo.address}'.`
  );

  hre.aragonToVerifyContracts.push({
    address: pluginRepo.address,
    args: [],
  });
};

export default func;
func.tags = ['CreateRepo'];

/**
 * Skips `PluginRepo` creation if the ENS name is claimed already
 * @param {HardhatRuntimeEnvironment} hre
 */
func.skip = async (hre: HardhatRuntimeEnvironment) => {
  console.log(`\n🏗️  ${path.basename(__filename)}:`);

  // Check if the ens record exists already
  const {pluginRepo} = await findPluginRepo(hre);

  if (pluginRepo !== null) {
    console.log(
      `Plugin Repo already deployed at '${
        pluginRepo.address
      }' on network '${getProductionNetworkName(hre)}'. Skipping deployment...`
    );

    hre.aragonToVerifyContracts.push({
      address: pluginRepo.address,
      args: [],
    });

    return true;
  } else {
    console.log('Deploying Plugin Repo');

    return false;
  }
};
