// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {MajorityVotingBase, IDAO} from "../MajorityVotingBase.sol";

contract MajorityVotingMock is MajorityVotingBase {
    function initializeMock(
        IDAO _dao,
        VotingSettings calldata _votingSettings,
        TargetConfig calldata _targetConfig,
        uint256 _minApprovals,
        bytes calldata _metadata
    ) public initializer {
        __MajorityVotingBase_init(_dao, _votingSettings, _targetConfig, _minApprovals, _metadata);
    }

    function createProposal(
        bytes calldata /* _metadata */,
        Action[] calldata /* _actions */,
        uint256 /* _allowFailureMap */,
        uint64 /* _startDate */,
        uint64 /* _endDate */,
        VoteOption /* _voteOption */,
        bool /* _tryEarlyExecution */
    ) public pure override returns (uint256 proposalId) {
        return 0;
    }

    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint64 _startDate,
        uint64 _endDate,
        bytes memory
    ) external pure override returns (uint256 proposalId) {
        // Calls public function for permission check.
        proposalId = createProposal(
            _metadata,
            _actions,
            0,
            _startDate,
            _endDate,
            VoteOption.None,
            false
        );
    }

    function customProposalParamsABI() external pure override returns (string memory) {
        return "[uint256 allowFailureMap, uint8 voteOption, bool tryEarlyExecution]";
    }

    function totalVotingPower(uint256 /* _blockNumber */) public pure override returns (uint256) {
        return 0;
    }

    /* solhint-disable no-empty-blocks */
    function _vote(
        uint256 /* _proposalId */,
        VoteOption /* _voteOption */,
        address /* _voter */,
        bool /* _tryEarlyExecution */
    ) internal pure override {}

    function _canVote(
        uint256 /* _proposalId */,
        address /* _voter */,
        VoteOption /* _voteOption */
    ) internal pure override returns (bool) {
        return true;
    }
}
