import {PLUGIN_CONTRACT_NAME} from '../../plugin-settings';
import {
  DAOMock,
  DAOMock__factory,
  MaciVoting,
  MaciVotingSetup__factory,
} from '../../typechain';
import '../../typechain/src/MaciVoting';
import {loadFixture} from '@nomicfoundation/hardhat-network-helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {ethers, upgrades} from 'hardhat';
import {Keypair, PrivKey} from 'maci-domainobjs';

const coordinatorMACIKeyPair = new Keypair(
  PrivKey.deserialize(
    'macisk.bdd73f1757f75261a0c9997def6cd47519cad2856347cdc6fd30718999576860'
  )
);

export const defaultInitData = {
  _maci: '0xE4721A80C6e56f4ebeed6acEE91b3ee715e7dD64', // TODO: setup MACI contract
  _coordinatorPubKey: coordinatorMACIKeyPair.pubKey.asContractParam(),
  _votingSettings: {
    minParticipation: 1,
    minDuration: 100,
    minProposerVotingPower: 1,
  },
};

export const STORE_PERMISSION_ID = ethers.utils.id('STORE_PERMISSION');

type FixtureResult = {
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  plugin: MaciVoting;
  daoMock: DAOMock;
};

async function fixture(): Promise<FixtureResult> {
  const [deployer, alice, bob] = await ethers.getSigners();
  const daoMock = await new DAOMock__factory(deployer).deploy();
  const plugin = (await upgrades.deployProxy(
    new MaciVotingSetup__factory(deployer),
    [
      daoMock.address,
      defaultInitData._maci,
      defaultInitData._coordinatorPubKey,
      defaultInitData._votingSettings,
    ],
    {
      kind: 'uups',
      initializer: 'initialize',
      unsafeAllow: ['constructor'],
      constructorArgs: [],
    }
  )) as unknown as MaciVoting;

  return {deployer, alice, bob, plugin, daoMock};
}

describe(PLUGIN_CONTRACT_NAME, function () {
  describe('initialize', async () => {
    it('reverts if trying to re-initialize', async () => {
      const {plugin, daoMock} = await loadFixture(fixture);
      await expect(
        plugin.initialize(
          daoMock.address,
          defaultInitData._maci,
          defaultInitData._coordinatorPubKey,
          defaultInitData._votingSettings
        )
      ).to.be.revertedWith('Initializable: contract is already initialized');
    });
  });
});
