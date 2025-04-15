// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {TokenVoting} from "./TokenVoting.sol";

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import {PermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

/// @title VotingPowerCondition
/// @author Aragon X - 2024
/// @notice Checks if an account's voting power or token balance meets the threshold set
///         in an associated TokenVoting plugin.
/// @custom:security-contact sirt@aragon.org
contract VotingPowerCondition is PermissionCondition {
    /// @notice The address of the `TokenVoting` plugin used to fetch voting power settings.
    TokenVoting private immutable TOKEN_VOTING;

    /// @notice The `IVotesUpgradeable` token interface used to check token balance.
    IVotesUpgradeable private immutable VOTING_TOKEN;

    /// @notice Initializes the contract with the `TokenVoting` plugin address and fetches the associated token.
    /// @param _tokenVoting The address of the `TokenVoting` plugin.
    constructor(address _tokenVoting) {
        TOKEN_VOTING = TokenVoting(_tokenVoting);
        VOTING_TOKEN = TOKEN_VOTING.getVotingToken();
    }

    /// @inheritdoc IPermissionCondition
    /// @dev The function checks both the voting power and token balance to ensure `_who` meets the minimum voting
    ///      threshold defined in the `TokenVoting` plugin. Returns `false` if the minimum requirement is unmet.
    function isGranted(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes calldata _data
    ) public view override returns (bool) {
        (_where, _data, _permissionId);

        uint256 minProposerVotingPower_ = TOKEN_VOTING.minProposerVotingPower();

        if (minProposerVotingPower_ != 0) {
            if (
                VOTING_TOKEN.getVotes(_who) < minProposerVotingPower_ &&
                IERC20Upgradeable(address(VOTING_TOKEN)).balanceOf(_who) < minProposerVotingPower_
            ) {
                return false;
            }
        }

        return true;
    }
}
