import {VERSION} from '../../plugin-settings';
import {ethers} from 'hardhat';

export const TOKEN_VOTING_INTERFACE = new ethers.utils.Interface([
  'function getVotingToken()',
]);

export const MAJORITY_VOTING_BASE_INTERFACE = new ethers.utils.Interface([
  'function minDuration()',
  'function minProposerVotingPower()',
  'function votingMode()',
  'function totalVotingPower(uint256)',
  'function getProposal(uint256)',
  'function updateVotingSettings(tuple(uint8,uint32,uint32,uint64,uint256))',
  'function createProposal(bytes,tuple(address,uint256,bytes)[],uint256,uint64,uint64,uint8,bool)',
]);

export const EXECUTE_PROPOSAL_PERMISSION_ID = ethers.utils.id(
  'EXECUTE_PROPOSAL_PERMISSION'
);

export const UPDATE_VOTING_SETTINGS_PERMISSION_ID = ethers.utils.id(
  'UPDATE_VOTING_SETTINGS_PERMISSION'
);

export const EXECUTE_PERMISSION_ID = ethers.utils.id('EXECUTE_PERMISSION');

export const CREATE_PROPOSAL_PERMISSION_ID = ethers.utils.id(
  'CREATE_PROPOSAL_PERMISSION'
);

export const MINT_PERMISSION_ID = ethers.utils.id('MINT_PERMISSION');

export const SET_TARGET_CONFIG_PERMISSION_ID = ethers.utils.id(
  'SET_TARGET_CONFIG_PERMISSION'
);

export const SET_METADATA_PERMISSION_ID = ethers.utils.id(
  'SET_METADATA_PERMISSION'
);

export const VOTING_EVENTS = {
  VOTING_SETTINGS_UPDATED: 'VotingSettingsUpdated',
  VOTE_CAST: 'VoteCast',
};

export const ANY_ADDR = '0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF';

export const INITIALIZE_SIGNATURE =
  'initialize(address,address,(uint256,uint256),(uint32,uint64,uint256))';

export const CREATE_PROPOSAL_SIGNATURE =
  'createProposal(bytes,(address,uint256,bytes)[],uint256,uint64,uint64,uint8,bool)';

export const CREATE_PROPOSAL_SIGNATURE_IProposal =
  'createProposal(bytes,(address,uint256,bytes)[],uint64,uint64,bytes)';

export enum Operation {
  call,
  delegatecall,
}

export type TargetConfig = {
  target: string;
  operation: number;
};

export const latestInitializerVersion = 2;
export const latestPluginBuild = VERSION.build;
