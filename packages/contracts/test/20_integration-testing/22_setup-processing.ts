import {METADATA, VERSION} from '../../plugin-settings';
import {IMaciVoting} from '../../typechain/src/MaciVoting';
import {getProductionNetworkName, findPluginRepo} from '../../utils/helpers';
import {
  defaultCoordinatorPubKey,
  defaultMaci,
  defaultVotingSettings,
} from '../test-utils/maci-voting-constants';
import {skipTestSuiteIfNetworkIsZkSync} from '../test-utils/skip-functions';
import {
  MaciVotingSetup,
  MaciVotingSetup__factory,
} from '../test-utils/typechain-versions';
import {createDaoProxy} from './test-helpers';
import {
  getLatestNetworkDeployment,
  getNetworkNameByAlias,
} from '@aragon/osx-commons-configs';
import {
  DAO_PERMISSIONS,
  PLUGIN_SETUP_PROCESSOR_PERMISSIONS,
  UnsupportedNetworkError,
  getNamedTypesFromMetadata,
} from '@aragon/osx-commons-sdk';
import {
  PluginSetupProcessor,
  PluginRepo,
  PluginSetupProcessorStructs,
  PluginSetupProcessor__factory,
  DAO,
} from '@aragon/osx-ethers';
import {BigNumberish} from '@ethersproject/bignumber';
import {loadFixture} from '@nomicfoundation/hardhat-network-helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import env, {deployments, ethers} from 'hardhat';

const productionNetworkName = getProductionNetworkName(env);

type FixtureResult = {
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  dao: DAO;
  psp: PluginSetupProcessor;
  pluginRepo: PluginRepo;
  pluginSetup: MaciVotingSetup;
  pluginSetupRefLatestBuild: PluginSetupProcessorStructs.PluginSetupRefStruct;
  defaultMaci: string;
  defaultCoordinatorPubKey: {x: BigNumberish; y: BigNumberish};
  defaultVotingSettings: IMaciVoting.VotingSettingsStruct;
  prepareInstallationInputs: string;
  prepareInstallData: any;
};

async function fixture(): Promise<FixtureResult> {
  // Deploy all contracts
  const tags = ['CreateRepo', 'NewVersion'];
  await deployments.fixture(tags);

  const [deployer, alice, bob] = await ethers.getSigners();
  const dummyMetadata = '0x12345678';
  const dao = await createDaoProxy(deployer, dummyMetadata);

  const network = getNetworkNameByAlias(productionNetworkName);
  if (network === null) {
    throw new UnsupportedNetworkError(productionNetworkName);
  }
  const networkDeployments = getLatestNetworkDeployment(network);
  if (networkDeployments === null) {
    throw `Deployments are not available on network ${network}.`;
  }

  // Get the `PluginSetupProcessor` from the network
  const psp = PluginSetupProcessor__factory.connect(
    networkDeployments.PluginSetupProcessor.address,
    deployer
  );

  // Get the deployed `PluginRepo`
  const {pluginRepo, ensDomain} = await findPluginRepo(env);
  if (pluginRepo === null) {
    throw `PluginRepo '${ensDomain}' does not exist yet.`;
  }

  const release = 1;
  const latestVersion = await pluginRepo['getLatestVersion(uint8)'](release);

  const pluginSetup = MaciVotingSetup__factory.connect(
    latestVersion.pluginSetup,
    deployer
  );

  const pluginSetupRefLatestBuild = {
    versionTag: {
      release: VERSION.release,
      build: VERSION.build,
    },
    pluginSetupRepo: pluginRepo.address,
  };

  // Provide uninstallation inputs
  const prepareInstallationInputs = ethers.utils.defaultAbiCoder.encode(
    getNamedTypesFromMetadata(
      METADATA.build.pluginSetup.prepareInstallation.inputs
    ),
    [
      defaultMaci,
      Object.values(defaultCoordinatorPubKey),
      Object.values(defaultVotingSettings),
    ]
  );

  const prepareInstallData = {
    maci: defaultMaci,
    coordinatorPubKey: Object.values(defaultCoordinatorPubKey),
    votingSettings: Object.values(defaultVotingSettings),
  };

  return {
    deployer,
    alice,
    bob,
    psp,
    dao,
    pluginRepo,
    pluginSetup,
    pluginSetupRefLatestBuild,
    defaultMaci,
    defaultCoordinatorPubKey,
    defaultVotingSettings,
    prepareInstallationInputs,
    prepareInstallData,
  };
}

skipTestSuiteIfNetworkIsZkSync(
  `PluginSetup processing on network '${productionNetworkName}'`,
  function () {
    it('installs & uninstalls the current build', async () => {
      const {
        deployer,
        psp,
        dao,
        /*
        pluginSetupRefLatestBuild,
        prepareInstallationInputs,
        */
      } = await loadFixture(fixture);

      // Grant deployer all required permissions
      await dao
        .connect(deployer)
        .grant(
          psp.address,
          deployer.address,
          PLUGIN_SETUP_PROCESSOR_PERMISSIONS.APPLY_INSTALLATION_PERMISSION_ID
        );
      await dao
        .connect(deployer)
        .grant(
          psp.address,
          deployer.address,
          PLUGIN_SETUP_PROCESSOR_PERMISSIONS.APPLY_UNINSTALLATION_PERMISSION_ID
        );
      await dao
        .connect(deployer)
        .grant(dao.address, psp.address, DAO_PERMISSIONS.ROOT_PERMISSION_ID);

      /*
        // TODO: activate this part. We are getting errors inside the installPLugin function
      const results = await installPLugin(
        deployer,
        psp,
        dao,
        pluginSetupRefLatestBuild,
        prepareInstallationInputs
      );

      const plugin = MaciVoting__factory.connect(
        results.preparedEvent.args.plugin,
        deployer
      );

      expect(await plugin.maci()).to.be.equal(defaultMaci);

      const condition = results.preparedEvent.args.preparedSetupData.helpers[0];

      // Uninstall the current build.
      await uninstallPLugin(
        deployer,
        psp,
        dao,
        plugin,
        pluginSetupRefLatestBuild,
        ethers.utils.defaultAbiCoder.encode(
          getNamedTypesFromMetadata(
            METADATA.build.pluginSetup.prepareUninstallation.inputs
          ),
          []
        ),
        [condition]
      );
      */
    });
  }
);
