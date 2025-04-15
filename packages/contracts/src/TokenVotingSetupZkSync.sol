// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {GovernanceERC20} from "./ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "./ERC20/governance/GovernanceWrappedERC20.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginUpgradeableSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";

import {MajorityVotingBase} from "./MajorityVotingBase.sol";
import {TokenVoting} from "./TokenVoting.sol";

import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import {VotingPowerCondition} from "./VotingPowerCondition.sol";

/// @title TokenVotingSetup
/// @author Aragon X - 2022-2024
/// @notice The setup contract of the `TokenVoting` plugin.
/// @dev v1.3 (Release 1, Build 3)
/// @custom:security-contact sirt@aragon.org
contract TokenVotingSetupZkSync is PluginUpgradeableSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    /// @notice The identifier of the `EXECUTE_PERMISSION` permission.
    bytes32 private constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice The ID of the permission required to call the `setTargetConfig` function.
    bytes32 private constant SET_TARGET_CONFIG_PERMISSION_ID =
        keccak256("SET_TARGET_CONFIG_PERMISSION");

    /// @notice The ID of the permission required to call the `setMetadata` function.
    bytes32 private constant SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION");

    /// @notice The ID of the permission required to call the `upgradeToAndCall` function.
    bytes32 private constant UPGRADE_PLUGIN_PERMISSION_ID = keccak256("UPGRADE_PLUGIN_PERMISSION");

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 private constant EXECUTE_PROPOSAL_PERMISSION_ID =
        keccak256("EXECUTE_PROPOSAL_PERMISSION");

    /// @notice A special address encoding permissions that are valid for any address `who` or `where`.
    address private constant ANY_ADDR = address(type(uint160).max);

    /// @notice The address of the `TokenVoting` base contract.
    // solhint-disable-next-line immutable-vars-naming
    TokenVoting private immutable tokenVotingBase;

    /// @notice Configuration settings for a token used within the governance system.
    /// @param addr The token address. If set to `address(0)`, a new `GovernanceERC20` token is deployed.
    ///     If the address implements `IVotes`, it will be used directly; otherwise,
    ///     it is wrapped as `GovernanceWrappedERC20`.
    /// @param name The name of the token, relevant only if a new token is deployed (i.e., `addr` is `address(0)`).
    /// @param symbol The symbol of the token, relevant only if a new token is deployed (i.e., `addr` is `address(0)`).
    struct TokenSettings {
        address addr;
        string name;
        string symbol;
    }

    /// @notice Thrown if the passed token address is not a token contract.
    /// @param token The token address
    error TokenNotContract(address token);

    /// @notice Thrown if token address is not ERC20.
    /// @param token The token address
    error TokenNotERC20(address token);

    /// @notice The contract constructor deploying the plugin implementation contract.
    constructor() PluginUpgradeableSetup(address(new TokenVoting())) {
        tokenVotingBase = TokenVoting(IMPLEMENTATION);
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Decode `_data` to extract the params needed for deploying and initializing `TokenVoting` plugin,
        // and the required helpers
        (
            MajorityVotingBase.VotingSettings memory votingSettings,
            TokenSettings memory tokenSettings,
            // only used for GovernanceERC20(token is not passed)
            GovernanceERC20.MintSettings memory mintSettings,
            IPlugin.TargetConfig memory targetConfig,
            uint256 minApprovals,
            bytes memory pluginMetadata
        ) = abi.decode(
                _data,
                (
                    MajorityVotingBase.VotingSettings,
                    TokenSettings,
                    GovernanceERC20.MintSettings,
                    IPlugin.TargetConfig,
                    uint256,
                    bytes
                )
            );

        address token = tokenSettings.addr;

        if (tokenSettings.addr != address(0)) {
            if (!token.isContract()) {
                revert TokenNotContract(token);
            }

            if (!_isERC20(token)) {
                revert TokenNotERC20(token);
            }

            if (!supportsIVotesInterface(token)) {
                token = address(
                    new GovernanceWrappedERC20(
                        IERC20Upgradeable(tokenSettings.addr),
                        tokenSettings.name,
                        tokenSettings.symbol
                    )
                );
            }
        } else {
            token = address(
                new GovernanceERC20(
                    IDAO(_dao),
                    tokenSettings.name,
                    tokenSettings.symbol,
                    mintSettings
                )
            );
        }

        // Prepare and deploy plugin proxy.
        plugin = address(tokenVotingBase).deployUUPSProxy(
            abi.encodeCall(
                TokenVoting.initialize,
                (
                    IDAO(_dao),
                    votingSettings,
                    IVotesUpgradeable(token),
                    targetConfig,
                    minApprovals,
                    pluginMetadata
                )
            )
        );

        preparedSetupData.helpers = new address[](2);
        preparedSetupData.helpers[0] = address(new VotingPowerCondition(plugin));
        preparedSetupData.helpers[1] = token;

        // Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](
                tokenSettings.addr != address(0) ? 6 : 7
            );

        // Set plugin permissions to be granted.
        // Grant the list of permissions of the plugin to the DAO.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenVotingBase.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        });

        // Grant `EXECUTE_PERMISSION` of the DAO to the plugin.
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        permissions[2] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.GrantWithCondition,
            plugin,
            ANY_ADDR,
            preparedSetupData.helpers[0], // VotingPowerCondition
            TokenVoting(IMPLEMENTATION).CREATE_PROPOSAL_PERMISSION_ID()
        );

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_TARGET_CONFIG_PERMISSION_ID
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_METADATA_PERMISSION_ID
        });

        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: ANY_ADDR,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PROPOSAL_PERMISSION_ID
        });

        if (tokenSettings.addr == address(0)) {
            bytes32 tokenMintPermission = GovernanceERC20(token).MINT_PERMISSION_ID();

            permissions[6] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: token,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: tokenMintPermission
            });
        }

        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    /// @dev Revoke the upgrade plugin permission to the DAO for all builds prior the current one (3).
    function prepareUpdate(
        address _dao,
        uint16 _fromBuild,
        SetupPayload calldata _payload
    )
        external
        override
        returns (bytes memory initData, PreparedSetupData memory preparedSetupData)
    {
        if (_fromBuild < 3) {
            address votingPowerCondition = address(new VotingPowerCondition(_payload.plugin));

            PermissionLib.MultiTargetPermission[]
                memory permissions = new PermissionLib.MultiTargetPermission[](5);

            permissions[0] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Revoke,
                where: _payload.plugin,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: UPGRADE_PLUGIN_PERMISSION_ID
            });

            permissions[1] = PermissionLib.MultiTargetPermission(
                PermissionLib.Operation.GrantWithCondition,
                _payload.plugin,
                ANY_ADDR, // ANY_ADDR
                votingPowerCondition,
                TokenVoting(IMPLEMENTATION).CREATE_PROPOSAL_PERMISSION_ID()
            );

            permissions[2] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: _payload.plugin,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: SET_TARGET_CONFIG_PERMISSION_ID
            });

            permissions[3] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: _payload.plugin,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: SET_METADATA_PERMISSION_ID
            });

            permissions[4] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: _payload.plugin,
                who: ANY_ADDR,
                condition: PermissionLib.NO_CONDITION,
                permissionId: EXECUTE_PROPOSAL_PERMISSION_ID
            });

            preparedSetupData.permissions = permissions;
            preparedSetupData.helpers = new address[](1);
            preparedSetupData.helpers[0] = votingPowerCondition;

            initData = abi.encodeCall(TokenVoting.initializeFrom, (_fromBuild, _payload.data));
        }
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // Prepare permissions.
        permissions = new PermissionLib.MultiTargetPermission[](6);

        // Set permissions to be Revoked.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenVotingBase.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_TARGET_CONFIG_PERMISSION_ID
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_METADATA_PERMISSION_ID
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: ANY_ADDR, // ANY_ADDR
            condition: PermissionLib.NO_CONDITION,
            permissionId: TokenVoting(IMPLEMENTATION).CREATE_PROPOSAL_PERMISSION_ID()
        });

        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: ANY_ADDR,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PROPOSAL_PERMISSION_ID
        });
    }

    /// @notice Unsatisfiably determines if the token is an IVotes interface.
    /// @dev Many tokens don't use ERC165 even though they still support IVotes.
    function supportsIVotesInterface(address token) public view returns (bool) {
        (bool success1, bytes memory data1) = token.staticcall(
            abi.encodeWithSelector(IVotesUpgradeable.getPastTotalSupply.selector, 0)
        );
        (bool success2, bytes memory data2) = token.staticcall(
            abi.encodeWithSelector(IVotesUpgradeable.getVotes.selector, address(this))
        );
        (bool success3, bytes memory data3) = token.staticcall(
            abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, address(this), 0)
        );

        return (success1 &&
            data1.length == 0x20 &&
            success2 &&
            data2.length == 0x20 &&
            success3 &&
            data3.length == 0x20);
    }

    /// @notice Unsatisfiably determines if the contract is an ERC20 token.
    /// @dev It's important to first check whether token is a contract prior to this call.
    /// @param token The token address
    function _isERC20(address token) private view returns (bool) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeCall(IERC20Upgradeable.balanceOf, (address(this)))
        );
        return success && data.length == 0x20;
    }
}
