// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IMaciVotingPlugin
/// @dev Release 1, Build 1
/// @notice Interface for the MACI voting plugin
interface IMaciVotingPlugin {
    /// @notice The voting settings
    struct VotingSettings {
        /// @notice The minimum duration of the proposal
        uint64 minDuration;
        /// @notice The minimum proposer voting power
        uint256 minProposerVotingPower;
        /// @notice The minimum participation
        uint32 minParticipation;
    }
}
