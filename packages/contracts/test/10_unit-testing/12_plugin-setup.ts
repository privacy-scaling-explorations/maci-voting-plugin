import {createDaoProxy} from '../20_integration-testing/test-helpers';
import {METADATA} from '../../plugin-settings';
import {IMaciVoting} from '../../typechain/src/MaciVoting';
import {loadFixtureCustom} from '../test-utils/fixture';
import {
  defaultCoordinatorPubKey,
  defaultMaci,
  defaultVotingSettings,
  getOnlyTheArrayResults,
} from '../test-utils/maci-voting-constants';
import {
  CREATE_PROPOSAL_PERMISSION_ID,
  TargetConfig,
  EXECUTE_PERMISSION_ID,
} from '../test-utils/token-voting-constants';
import {Operation as Op} from '../test-utils/token-voting-constants';
import {MaciVotingSetup} from '../test-utils/typechain-versions';
import {ARTIFACT_SOURCES} from '../test-utils/wrapper';
import {Operation} from '@aragon/osx-commons-sdk';
import {getNamedTypesFromMetadata} from '@aragon/osx-commons-sdk';
import {pctToRatio} from '@aragon/osx-commons-sdk';
import {DAO} from '@aragon/osx-ethers';
import {BigNumber, BigNumberish} from '@ethersproject/bignumber';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import hre, {ethers} from 'hardhat';

const abiCoder = ethers.utils.defaultAbiCoder;
const AddressZero = ethers.constants.AddressZero;

type FixtureResult = {
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  carol: SignerWithAddress;
  pluginSetup: MaciVotingSetup;
  defaultMaci: string;
  defaultCoordinatorPubKey: {x: BigNumberish; y: BigNumberish};
  defaultVotingSettings: IMaciVoting.VotingSettingsStruct;
  updateMinApproval: BigNumber;
  updateMetadata: string;
  updateTargetConfig: TargetConfig;
  prepareInstallationInputs: string;
  prepareUninstallationInputs: string;
  dao: DAO;
};

async function fixture(): Promise<FixtureResult> {
  const [deployer, alice, bob, carol] = await ethers.getSigners();

  // Deploy a DAO proxy.
  const dummyMetadata = '0x12345678';
  const dao = await createDaoProxy(deployer, dummyMetadata);

  const pluginSetup = await hre.wrapper.deploy(
    ARTIFACT_SOURCES.MaciVotingSetup,
    {}
  );

  // Provide installation inputs
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

  // Provide uninstallation inputs
  const prepareUninstallationInputs = ethers.utils.defaultAbiCoder.encode(
    getNamedTypesFromMetadata(
      METADATA.build.pluginSetup.prepareUninstallation.inputs
    ),
    []
  );

  const updateMinApproval = pctToRatio(35);
  const updateTargetConfig: TargetConfig = {
    target: pluginSetup.address,
    operation: Op.call,
  };
  const updateMetadata: string = '0x11';

  return {
    deployer,
    alice,
    bob,
    carol,
    pluginSetup,
    defaultMaci,
    defaultCoordinatorPubKey,
    defaultVotingSettings,
    updateMinApproval,
    updateTargetConfig,
    updateMetadata,
    prepareInstallationInputs,
    prepareUninstallationInputs,
    dao,
  };
}

describe('MaciVotingSetup', function () {
  it('does not support the empty interface', async () => {
    const {pluginSetup} = await loadFixtureCustom(fixture);
    expect(await pluginSetup.supportsInterface('0xffffffff')).to.be.false;
  });

  describe('prepareInstallation', async () => {
    it('fails if data is empty, or not of minimum length', async () => {
      const {pluginSetup, dao, prepareInstallationInputs} =
        await loadFixtureCustom(fixture);

      // Try calling `prepareInstallation` without input data.
      await expect(pluginSetup.prepareInstallation(dao.address, [])).to.be
        .reverted;

      // Try calling `prepareInstallation` with input data of wrong length.
      const trimmedData = prepareInstallationInputs.substring(
        0,
        prepareInstallationInputs.length - 100
      );
      await expect(pluginSetup.prepareInstallation(dao.address, trimmedData)).to
        .be.reverted;

      // Check that `prepareInstallation` can be called with the correct input data.
      await expect(
        pluginSetup.prepareInstallation(dao.address, prepareInstallationInputs)
      ).not.to.be.reverted;
    });

    it('correctly returns plugin, helpers and permissions, when installation parameters are provided', async () => {
      const {pluginSetup, dao, defaultVotingSettings} = await loadFixtureCustom(
        fixture
      );

      const data = abiCoder.encode(
        getNamedTypesFromMetadata(
          METADATA.build.pluginSetup.prepareInstallation.inputs
        ),
        [
          defaultMaci,
          defaultCoordinatorPubKey,
          Object.values(defaultVotingSettings),
        ]
      );

      const {
        plugin,
        preparedSetupData: {permissions},
      } = await pluginSetup.callStatic.prepareInstallation(dao.address, data);

      expect(permissions.length).to.be.equal(2);
      expect(getOnlyTheArrayResults(permissions)).to.deep.equal([
        [
          Operation.Grant,
          plugin,
          dao.address,
          AddressZero,
          CREATE_PROPOSAL_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          plugin,
          dao.address,
          AddressZero,
          EXECUTE_PERMISSION_ID,
        ],
      ]);
    });
  });

  describe('prepareUninstallation', async () => {
    it('correctly returns permissions, when the required number of helpers is supplied', async () => {
      const {pluginSetup, dao, prepareUninstallationInputs} =
        await loadFixtureCustom(fixture);

      const plugin = ethers.Wallet.createRandom().address;

      const essentialPermissions = [
        [
          Operation.Revoke,
          plugin,
          dao.address,
          AddressZero,
          CREATE_PROPOSAL_PERMISSION_ID,
        ],
        [
          Operation.Revoke,
          plugin,
          dao.address,
          AddressZero,
          EXECUTE_PERMISSION_ID,
        ],
      ];

      const permissions = await pluginSetup.callStatic.prepareUninstallation(
        dao.address,
        {
          plugin,
          currentHelpers: [],
          data: prepareUninstallationInputs,
        }
      );

      expect(permissions.length).to.be.equal(2);
      expect(getOnlyTheArrayResults(permissions)).to.deep.equal(
        essentialPermissions
      );
    });
  });
});
