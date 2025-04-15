# TokenVoting Plugin

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the [Aragon OSx Plugin Versioning Convention](https://devs.aragon.org/docs/osx/how-to-guides/plugin-development/publication/versioning).

## v1.3

### Added

- Copied files from [aragon/osx commit 1130df](https://github.com/aragon/osx/commit/1130dfce94fd294c4341e91a8f3faccc54cf43b7)
- `createProposal` standardized function.
- `createProposal` function is auth protected.
- `ListedCheckCondition` permission condition to grant the create proposal permission. This condition will allow the creation based on plugin's setup.
- `execute` function is auth protected, when the plugin is installed this permission will be granted to `ANY_ADDRESS`.
- The plugin inherits now from `MetadataExtensionUpgradeable`, meaning that the plugin has metadata that can be get/set (`getMetadata`, `setMetadata`).
- `initialize` function receives also `pluginMetadata` and `TargetConfig`.
- `hasSucceeded` and `customProposalParamsABI` function implementing to `IProposal` interface.
- `minApproval` configuration to the plugin, to restrict the minimal amount of approvals needed to the proposal succeed.

### Changed

- Bumped OpenZepplin to `4.9.6`.
- Used `ProxyLib` from `osx-commons-contracts` for the UUPS proxy deployment in `TokenVotingSetup`.
- Hard-coded the `bytes32 internal constant EXECUTE_PERMISSION_ID` constant in `TokenVotingSetup` until it is available in `PermissionLib`.
- Changed the `prepareInstallation` function in `TokenVotingSetup` to not unnecessarily grant the `UPGRADE_PLUGIN_PERMISSION_ID` permission to the installing DAO.
- Changed the `prepareUpdate` function in `TokenVotingSetup` to revoke the previously unnecessarily granted `UPGRADE_PLUGIN_PERMISSION_ID` permission from the installing DAO.
- Changed the `prepareUninstallation` function in `TokenVotingSetup` to not revoke the `MINT_PERMISSION_ID` to the DAO when the plugin is uninstalled.
