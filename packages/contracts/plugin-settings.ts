import buildMetadata from './src/build-metadata.json';
import releaseMetadata from './src/release-metadata.json';

export const PLUGIN_REPO_PROXY_NAME = 'TokenVotingProxy';
export const PLUGIN_CONTRACT_NAME = 'MaciVoting'; // This must match the filename `packages/contracts/src/MyPlugin.sol` and the contract name `MyPlugin` within.
export const PLUGIN_SETUP_CONTRACT_NAME = 'MaciVotingSetup'; // This must match the filename `packages/contracts/src/MyPluginSetup.sol` and the contract name `MyPluginSetup` within.

export const PLUGIN_REPO_ENS_SUBDOMAIN_NAME = 'maci-voting'; // This will result in the ENS domain name 'my.plugin.dao.eth'

export const GOVERNANCE_ERC20_CONTRACT_NAME = 'GovernanceERC20';
export const GOVERNANCE_WRAPPED_ERC20_CONTRACT_NAME = 'GovernanceWrappedERC20';

export const VOTING_POWER_CONDITION_CONTRACT_NAME = 'VotingPowerCondition';

export const VERSION = {
  release: 1, // Increment this number ONLY if breaking/incompatible changes were made. Updates between releases are NOT possible.
  build: 3, // Increment this number if non-breaking/compatible changes were made. Updates to newer builds are possible.
};

// The metadata associated with the plugin version you are currently working on.
// For more details, visit https://devs.aragon.org/docs/osx/how-to-guides/plugin-development/publication/metadata.
// Don't change this unless you know what you are doing.
export const METADATA = {
  build: buildMetadata,
  release: releaseMetadata,
};
