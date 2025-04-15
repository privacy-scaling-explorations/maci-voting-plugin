import {createDaoProxy} from '../20_integration-testing/test-helpers';
import {TestGovernanceERC20} from '../../typechain';
import {IMaciVoting} from '../../typechain/src/MaciVoting';
import {loadFixtureCustom} from '../test-utils/fixture';
import {
  defaultCoordinatorPubKey,
  defaultMaci,
  defaultVotingSettings,
} from '../test-utils/maci-voting-constants';
import {
  UPDATE_VOTING_SETTINGS_PERMISSION_ID,
  EXECUTE_PROPOSAL_PERMISSION_ID,
  CREATE_PROPOSAL_PERMISSION_ID,
  ANY_ADDR,
} from '../test-utils/token-voting-constants';
import {TokenVoting, MaciVoting} from '../test-utils/typechain-versions';
import {ARTIFACT_SOURCES} from '../test-utils/wrapper';
import {DAO_PERMISSIONS} from '@aragon/osx-commons-sdk';
import {DAO, DAOStructs} from '@aragon/osx-ethers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {BigNumberish} from 'ethers';
import hre, {ethers} from 'hardhat';

type GlobalFixtureResult = {
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  carol: SignerWithAddress;
  dave: SignerWithAddress;
  eve: SignerWithAddress;
  frank: SignerWithAddress;
  grace: SignerWithAddress;
  harold: SignerWithAddress;
  ivan: SignerWithAddress;
  judy: SignerWithAddress;
  mallory: SignerWithAddress;
  initializedPlugin: MaciVoting;
  uninitializedPlugin: MaciVoting;
  token: TestGovernanceERC20;
  dao: DAO;
  defaultMaci: string;
  defaultCoordinatorPubKey: {x: BigNumberish; y: BigNumberish};
  defaultVotingSettings: IMaciVoting.VotingSettingsStruct;
  dummyActions: DAOStructs.ActionStruct[];
  dummyMetadata: string;
};

async function globalFixture(): Promise<GlobalFixtureResult> {
  const [
    deployer,
    alice,
    bob,
    carol,
    dave,
    eve,
    frank,
    grace,
    harold,
    ivan,
    judy,
    mallory,
  ] = await ethers.getSigners();

  // Deploy a DAO proxy.
  const dummyMetadata = '0x12345678';
  const dao = await createDaoProxy(deployer, dummyMetadata);

  // Deploy a plugin proxy factory containing the plugin implementation.

  const token = await hre.wrapper.deploy(ARTIFACT_SOURCES.TestGovernanceERC20, {
    args: [
      dao.address,
      'gov',
      'GOV',
      {
        receivers: [],
        amounts: [],
      },
    ],
  });

  // Deploy an initialized plugin proxy.

  const initializedPlugin = await hre.wrapper.deploy(
    ARTIFACT_SOURCES.MaciVoting,
    {withProxy: true}
  );

  await initializedPlugin.initialize(
    dao.address,
    defaultMaci,
    defaultCoordinatorPubKey,
    defaultVotingSettings
  );

  // Grant ANY_ADDR the permission to execute proposals
  await dao
    .connect(deployer)
    .grant(initializedPlugin.address, ANY_ADDR, EXECUTE_PROPOSAL_PERMISSION_ID);

  // Grant deployer the permission to update the voting settings
  await dao
    .connect(deployer)
    .grant(
      initializedPlugin.address,
      deployer.address,
      UPDATE_VOTING_SETTINGS_PERMISSION_ID
    );

  // Grant the plugin the permission to execute on the DAO
  await dao
    .connect(deployer)
    .grant(
      dao.address,
      initializedPlugin.address,
      DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
    );

  // Deploy an uninitialized plugin proxy.
  const uninitializedPlugin = await hre.wrapper.deploy(
    ARTIFACT_SOURCES.MaciVoting,
    {
      withProxy: true,
    }
  );

  // Provide a dummy action array.
  const dummyActions: DAOStructs.ActionStruct[] = [
    {
      to: deployer.address,
      data: '0x1234',
      value: 0,
    },
  ];

  await grantCreateProposalPermissions(
    deployer,
    dao,
    initializedPlugin,
    uninitializedPlugin
  );

  return {
    deployer,
    alice,
    bob,
    carol,
    dave,
    eve,
    frank,
    grace,
    harold,
    ivan,
    judy,
    mallory,
    initializedPlugin,
    uninitializedPlugin,
    defaultMaci,
    defaultCoordinatorPubKey,
    defaultVotingSettings,
    token,
    dao,
    dummyActions,
    dummyMetadata,
  };
}

async function grantCreateProposalPermissions(
  deployer: SignerWithAddress,
  dao: DAO,
  initializedPlugin: TokenVoting,
  uninitializedPlugin: TokenVoting
) {
  const condition = await hre.wrapper.deploy(
    ARTIFACT_SOURCES.VotingPowerCondition,
    {
      args: [initializedPlugin.address],
    }
  );

  await dao.grantWithCondition(
    initializedPlugin.address,
    ANY_ADDR,
    CREATE_PROPOSAL_PERMISSION_ID,
    condition.address
  );

  await dao.grantWithCondition(
    uninitializedPlugin.address,
    ANY_ADDR,
    CREATE_PROPOSAL_PERMISSION_ID,
    condition.address
  );
}

describe('MaciVoting', function () {
  describe('initialize', async () => {
    it('reverts if trying to re-initialize', async () => {
      const {
        dao,
        initializedPlugin,
        defaultMaci,
        defaultCoordinatorPubKey,
        defaultVotingSettings,
      } = await loadFixtureCustom(globalFixture);

      // Try to reinitialize the initialized plugin.
      await expect(
        initializedPlugin.initialize(
          dao.address,
          defaultMaci,
          defaultCoordinatorPubKey,
          defaultVotingSettings
        )
      ).to.be.revertedWith('Initializable: contract is already initialized');
    });

    it('sets the voting settings, maci contract and coordinator pubkeys', async () => {
      const {
        dao,
        uninitializedPlugin: plugin,
        defaultMaci,
        defaultCoordinatorPubKey,
        defaultVotingSettings,
        // token,
      } = await loadFixtureCustom(globalFixture);

      // Check that the uninitialized plugin doesn't have voting settings and token set yet.
      expect((await plugin.votingSettings()).minDuration).to.equal(0);
      expect(await plugin.minParticipation()).to.equal(0);
      expect(await plugin.minProposerVotingPower()).to.equal(0);
      expect(await plugin.getVotingToken()).to.equal(
        ethers.constants.AddressZero
      );

      // Initialize the plugin.
      await plugin.initialize(
        dao.address,
        defaultMaci,
        defaultCoordinatorPubKey,
        defaultVotingSettings
      );

      // Check that the maci contract has been set.
      expect(await plugin.maci()).to.equal(defaultMaci);

      // Check that the coordinator pubkey has been set.
      expect((await plugin.coordinatorPubKey()).x).to.equal(
        defaultCoordinatorPubKey.x
      );
      expect((await plugin.coordinatorPubKey()).y).to.equal(
        defaultCoordinatorPubKey.y
      );

      // Check that the voting settings have been set.
      expect((await plugin.votingSettings()).minDuration).to.equal(
        defaultVotingSettings.minDuration
      );
      expect(await plugin.minParticipation()).to.equal(
        defaultVotingSettings.minParticipation
      );
      expect(await plugin.minProposerVotingPower()).to.equal(
        defaultVotingSettings.minProposerVotingPower
      );
    });
  });
});
