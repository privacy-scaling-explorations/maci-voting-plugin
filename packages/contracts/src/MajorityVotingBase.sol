// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/* solhint-disable max-line-length */

import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {ProposalUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";
import {RATIO_BASE, RatioOutOfBounds} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {MetadataExtensionUpgradeable} from "@aragon/osx-commons-contracts/src/utils/metadata/MetadataExtensionUpgradeable.sol";

import {IMajorityVoting} from "./IMajorityVoting.sol";

/* solhint-enable max-line-length */

/// @title MajorityVotingBase
/// @author Aragon X - 2022-2024
/// @notice The abstract implementation of majority voting plugins.
///
/// ### Parameterization
///
/// We define two parameters
/// $$\texttt{support} = \frac{N_\text{yes}}{N_\text{yes} + N_\text{no}} \in [0,1]$$
/// and
/// $$\texttt{participation} = \frac{N_\text{yes} + N_\text{no} + N_\text{abstain}}{N_\text{total}} \in [0,1],$$
/// where $N_\text{yes}$, $N_\text{no}$, and $N_\text{abstain}$ are the yes, no, and abstain votes that have been
/// cast and $N_\text{total}$ is the total voting power available at proposal creation time.
///
/// #### Limit Values: Support Threshold & Minimum Participation
///
/// Two limit values are associated with these parameters and decide if a proposal execution should be possible:
/// $\texttt{supportThreshold} \in [0,1)$ and $\texttt{minParticipation} \in [0,1]$.
///
/// For threshold values, $>$ comparison is used. This **does not** include the threshold value.
/// E.g., for $\texttt{supportThreshold} = 50\%$,
/// the criterion is fulfilled if there is at least one more yes than no votes ($N_\text{yes} = N_\text{no} + 1$).
/// For minimum values, $\ge{}$ comparison is used. This **does** include the minimum participation value.
/// E.g., for $\texttt{minParticipation} = 40\%$ and $N_\text{total} = 10$,
/// the criterion is fulfilled if 4 out of 10 votes were casted.
///
/// Majority voting implies that the support threshold is set with
/// $$\texttt{supportThreshold} \ge 50\% .$$
/// However, this is not enforced by the contract code and developers can make unsafe parameters and
/// only the frontend will warn about bad parameter settings.
///
/// ### Execution Criteria
///
/// After the vote is closed, two criteria decide if the proposal passes.
///
/// #### The Support Criterion
///
/// For a proposal to pass, the required ratio of yes and no votes must be met:
/// $$(1- \texttt{supportThreshold}) \cdot N_\text{yes} > \texttt{supportThreshold} \cdot N_\text{no}.$$
/// Note, that the inequality yields the simple majority voting condition for $\texttt{supportThreshold}=\frac{1}{2}$.
///
/// #### The Participation Criterion
///
/// For a proposal to pass, the minimum voting power must have been cast:
/// $$N_\text{yes} + N_\text{no} + N_\text{abstain} \ge \texttt{minVotingPower},$$
/// where $\texttt{minVotingPower} = \texttt{minParticipation} \cdot N_\text{total}$.
///
/// ### Vote Replacement
///
/// The contract allows votes to be replaced. Voters can vote multiple times
/// and only the latest voteOption is tallied.
///
/// ### Early Execution
///
/// This contract allows a proposal to be executed early,
/// iff the vote outcome cannot change anymore by more people voting.
/// Accordingly, vote replacement and early execution are mutually exclusive options.
/// The outcome cannot change anymore
/// iff the support threshold is met even if all remaining votes are no votes.
/// We call this number the worst-case number of no votes and define it as
///
/// $$N_\text{no, worst-case} = N_\text{no} + \texttt{remainingVotes}$$
///
/// where
///
/// $$\texttt{remainingVotes} =
/// N_\text{total}-\underbrace{(N_\text{yes}+N_\text{no}+N_\text{abstain})}_{\text{turnout}}.$$
///
/// We can use this quantity to calculate the worst-case support that would be obtained
/// if all remaining votes are casted with no:
///
/// $$
/// \begin{align*}
///   \texttt{worstCaseSupport}
///   &= \frac{N_\text{yes}}{N_\text{yes} + (N_\text{no, worst-case})} \\[3mm]
///   &= \frac{N_\text{yes}}{N_\text{yes} + (N_\text{no} + \texttt{remainingVotes})} \\[3mm]
///   &= \frac{N_\text{yes}}{N_\text{yes} +  N_\text{no} + N_\text{total}
///      - (N_\text{yes} + N_\text{no} + N_\text{abstain})} \\[3mm]
///   &= \frac{N_\text{yes}}{N_\text{total} - N_\text{abstain}}
/// \end{align*}
/// $$
///
/// In analogy, we can modify [the support criterion](#the-support-criterion)
/// from above to allow for early execution:
///
/// $$
/// \begin{align*}
///   (1 - \texttt{supportThreshold}) \cdot N_\text{yes}
///   &> \texttt{supportThreshold} \cdot  N_\text{no, worst-case} \\[3mm]
///   &> \texttt{supportThreshold} \cdot (N_\text{no} + \texttt{remainingVotes}) \\[3mm]
///   &> \texttt{supportThreshold} \cdot (N_\text{no}
///     + N_\text{total}-(N_\text{yes}+N_\text{no}+N_\text{abstain})) \\[3mm]
///   &> \texttt{supportThreshold} \cdot (N_\text{total} - N_\text{yes} - N_\text{abstain})
/// \end{align*}
/// $$
///
/// Accordingly, early execution is possible when the vote is open,
///     the modified support criterion, and the particicpation criterion are met.
/// @dev This contract implements the `IMajorityVoting` interface.
/// @custom:security-contact sirt@aragon.org
abstract contract MajorityVotingBase is
    IMajorityVoting,
    Initializable,
    ERC165Upgradeable,
    MetadataExtensionUpgradeable,
    PluginUUPSUpgradeable,
    ProposalUpgradeable
{
    using SafeCastUpgradeable for uint256;

    /// @notice The different voting modes available.
    /// @param Standard In standard mode, early execution and vote replacement are disabled.
    /// @param EarlyExecution In early execution mode, a proposal can be executed
    ///     early before the end date if the vote outcome cannot mathematically change by more voters voting.
    /// @param VoteReplacement In vote replacement mode, voters can change their vote
    ///     multiple times and only the latest vote option is tallied.
    enum VotingMode {
        Standard,
        EarlyExecution,
        VoteReplacement
    }

    /// @notice A container for the majority voting settings that will be applied as parameters on proposal creation.
    /// @param votingMode A parameter to select the vote mode.
    ///     In standard mode (0), early execution and vote replacement are disabled.
    ///     In early execution mode (1), a proposal can be executed early before the end date
    ///     if the vote outcome cannot mathematically change by more voters voting.
    ///     In vote replacement mode (2), voters can change their vote multiple times
    ///     and only the latest vote option is tallied.
    /// @param supportThreshold The support threshold value.
    ///     Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minParticipation The minimum participation value.
    ///     Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minDuration The minimum duration of the proposal vote in seconds.
    /// @param minProposerVotingPower The minimum voting power required to create a proposal.
    struct VotingSettings {
        VotingMode votingMode;
        uint32 supportThreshold;
        uint32 minParticipation;
        uint64 minDuration;
        uint256 minProposerVotingPower;
    }

    /// @notice A container for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param parameters The proposal parameters at the time of the proposal creation.
    /// @param tally The vote tally of the proposal.
    /// @param voters The votes casted by the voters.
    /// @param actions The actions to be executed when the proposal passes.
    /// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert.
    ///     If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts.
    ///     A failure map value of 0 requires every action to not revert.
    /// @param minApprovalPower The minimum amount of yes votes power needed for the proposal advance.
    /// @param targetConfig Configuration for the execution target, specifying the target address and operation type
    ///     (either `Call` or `DelegateCall`). Defined by `TargetConfig` in the `IPlugin` interface,
    ///     part of the `osx-commons-contracts` package, added in build 3.
    struct Proposal {
        bool executed;
        ProposalParameters parameters;
        Tally tally;
        mapping(address => IMajorityVoting.VoteOption) voters;
        Action[] actions;
        uint256 allowFailureMap;
        uint256 minApprovalPower;
        TargetConfig targetConfig; // added in v1.3
    }

    /// @notice A container for the proposal parameters at the time of proposal creation.
    /// @param votingMode A parameter to select the vote mode.
    /// @param supportThreshold The support threshold value.
    ///     The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param startDate The start date of the proposal vote.
    /// @param endDate The end date of the proposal vote.
    /// @param snapshotBlock The number of the block prior to the proposal creation.
    /// @param minVotingPower The minimum voting power needed for a proposal to reach minimum participation.
    struct ProposalParameters {
        VotingMode votingMode;
        uint32 supportThreshold;
        uint64 startDate;
        uint64 endDate;
        uint64 snapshotBlock;
        uint256 minVotingPower;
    }

    /// @notice A container for the proposal vote tally.
    /// @param abstain The number of abstain votes casted.
    /// @param yes The number of yes votes casted.
    /// @param no The number of no votes casted.
    struct Tally {
        uint256 abstain;
        uint256 yes;
        uint256 no;
    }

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 internal constant MAJORITY_VOTING_BASE_INTERFACE_ID =
        this.minDuration.selector ^
            this.minProposerVotingPower.selector ^
            this.votingMode.selector ^
            this.totalVotingPower.selector ^
            this.getProposal.selector ^
            this.updateVotingSettings.selector ^
            this.updateMinApprovals.selector ^
            bytes4(
                keccak256(
                    "createProposal(bytes,(address,uint256,bytes)[],uint256,uint64,uint64,uint8,bool)"
                )
            );

    /// @notice The ID of the permission required to call the `updateVotingSettings` function.
    bytes32 public constant UPDATE_VOTING_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_VOTING_SETTINGS_PERMISSION");

    /// @notice The ID of the permission required to call the `createProposal` functions.
    bytes32 public constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 public constant EXECUTE_PROPOSAL_PERMISSION_ID =
        keccak256("EXECUTE_PROPOSAL_PERMISSION");

    /// @notice A mapping between proposal IDs and proposal information.
    // solhint-disable-next-line named-parameters-mapping
    mapping(uint256 => Proposal) internal proposals;

    /// @notice The struct storing the voting settings.
    VotingSettings private votingSettings;

    /// @notice The minimum ratio of yes votes needed for a proposal to succeed.
    /// @dev Not included in VotingSettings for compatibility reasons.
    uint256 private minApprovals; // added in v1.3

    /// @notice Thrown if a date is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error DateOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown if the minimal duration value is out of bounds (less than one hour or greater than 1 year).
    /// @param limit The limit value.
    /// @param actual The actual value.
    error MinDurationOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown when a sender is not allowed to create a proposal.
    /// @param sender The sender address.
    error ProposalCreationForbidden(address sender);

    /// @notice Thrown when a proposal doesn't exist.
    /// @param proposalId The ID of the proposal which doesn't exist.
    error NonexistentProposal(uint256 proposalId);

    /// @notice Thrown if an account is not allowed to cast a vote. This can be because the vote
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the account doesn't have voting powers.
    /// @param proposalId The ID of the proposal.
    /// @param account The address of the _account.
    /// @param voteOption The chosen vote option.
    error VoteCastForbidden(uint256 proposalId, address account, VoteOption voteOption);

    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);

    /// @notice Thrown if the proposal with same actions and metadata already exists.
    /// @param proposalId The id of the proposal.
    error ProposalAlreadyExists(uint256 proposalId);

    /// @notice Emitted when the voting settings are updated.
    /// @param votingMode A parameter to select the vote mode.
    /// @param supportThreshold The support threshold value.
    /// @param minParticipation The minimum participation value.
    /// @param minDuration The minimum duration of the proposal vote in seconds.
    /// @param minProposerVotingPower The minimum voting power required to create a proposal.
    event VotingSettingsUpdated(
        VotingMode votingMode,
        uint32 supportThreshold,
        uint32 minParticipation,
        uint64 minDuration,
        uint256 minProposerVotingPower
    );

    /// @notice Emitted when the min approval value is updated.
    /// @param minApprovals The minimum amount of yes votes needed for a proposal succeed.
    event VotingMinApprovalUpdated(uint256 minApprovals);

    /// @notice Initializes the component to be used by inheriting contracts.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _votingSettings The voting settings.
    /// @param _targetConfig Configuration for the execution target, specifying the target address and operation type
    ///     (either `Call` or `DelegateCall`). Defined by `TargetConfig` in the `IPlugin` interface,
    ///     part of the `osx-commons-contracts` package, added in build 3.
    /// @param _minApprovals The minimal amount of approvals the proposal needs to succeed.
    /// @param _pluginMetadata The plugin specific information encoded in bytes.
    ///     This can also be an ipfs cid encoded in bytes.
    // solhint-disable-next-line func-name-mixedcase
    function __MajorityVotingBase_init(
        IDAO _dao,
        VotingSettings calldata _votingSettings,
        TargetConfig calldata _targetConfig,
        uint256 _minApprovals,
        bytes calldata _pluginMetadata
    ) internal onlyInitializing {
        __PluginUUPSUpgradeable_init(_dao);
        _updateVotingSettings(_votingSettings);
        _updateMinApprovals(_minApprovals);
        _setTargetConfig(_targetConfig);
        _setMetadata(_pluginMetadata);
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    )
        public
        view
        virtual
        override(
            ERC165Upgradeable,
            MetadataExtensionUpgradeable,
            PluginUUPSUpgradeable,
            ProposalUpgradeable
        )
        returns (bool)
    {
        // In addition to the current IMajorityVoting interface, also support previous version
        // that did not include the `isMinApprovalReached` and `minApproval` functions, same
        // happens with MAJORITY_VOTING_BASE_INTERFACE which did not include `updateMinApprovals`.
        return
            _interfaceId == MAJORITY_VOTING_BASE_INTERFACE_ID ||
            _interfaceId == MAJORITY_VOTING_BASE_INTERFACE_ID ^ this.updateMinApprovals.selector ||
            _interfaceId == type(IMajorityVoting).interfaceId ||
            _interfaceId ==
            type(IMajorityVoting).interfaceId ^
                this.isMinApprovalReached.selector ^
                this.minApproval.selector ||
            super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc IMajorityVoting
    function vote(
        uint256 _proposalId,
        VoteOption _voteOption,
        bool _tryEarlyExecution
    ) public virtual {
        address account = _msgSender();

        if (!_canVote(_proposalId, account, _voteOption)) {
            revert VoteCastForbidden({
                proposalId: _proposalId,
                account: account,
                voteOption: _voteOption
            });
        }
        _vote(_proposalId, _voteOption, account, _tryEarlyExecution);
    }

    /// @inheritdoc IProposal
    /// @dev Requires the `EXECUTE_PROPOSAL_PERMISSION_ID` permission.
    function execute(
        uint256 _proposalId
    ) public virtual override(IMajorityVoting, IProposal) auth(EXECUTE_PROPOSAL_PERMISSION_ID) {
        if (!_canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }
        _execute(_proposalId);
    }

    /// @inheritdoc IMajorityVoting
    function getVoteOption(
        uint256 _proposalId,
        address _voter
    ) public view virtual returns (VoteOption) {
        return proposals[_proposalId].voters[_voter];
    }

    /// @inheritdoc IMajorityVoting
    /// @dev Reverts if the proposal with the given `_proposalId` does not exist.
    function canVote(
        uint256 _proposalId,
        address _account,
        VoteOption _voteOption
    ) public view virtual returns (bool) {
        if (!_proposalExists(_proposalId)) {
            revert NonexistentProposal(_proposalId);
        }

        return _canVote(_proposalId, _account, _voteOption);
    }

    /// @inheritdoc IMajorityVoting
    /// @dev Reverts if the proposal with the given `_proposalId` does not exist.
    function canExecute(
        uint256 _proposalId
    ) public view virtual override(IMajorityVoting, IProposal) returns (bool) {
        if (!_proposalExists(_proposalId)) {
            revert NonexistentProposal(_proposalId);
        }

        return _canExecute(_proposalId);
    }

    /// @inheritdoc IProposal
    /// @dev Reverts if the proposal with the given `_proposalId` does not exist.
    function hasSucceeded(uint256 _proposalId) public view virtual returns (bool) {
        if (!_proposalExists(_proposalId)) {
            revert NonexistentProposal(_proposalId);
        }

        Proposal storage proposal_ = proposals[_proposalId];
        bool isProposalOpen = _isProposalOpen(proposal_);

        return _hasSucceeded(_proposalId, isProposalOpen);
    }

    /// @inheritdoc IMajorityVoting
    function isSupportThresholdReached(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The code below implements the formula of the support criterion explained in the top of this file.
        // `(1 - supportThreshold) * N_yes > supportThreshold *  N_no`
        return
            (RATIO_BASE - proposal_.parameters.supportThreshold) * proposal_.tally.yes >
            proposal_.parameters.supportThreshold * proposal_.tally.no;
    }

    /// @inheritdoc IMajorityVoting
    function isSupportThresholdReachedEarly(
        uint256 _proposalId
    ) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        uint256 noVotesWorstCase = totalVotingPower(proposal_.parameters.snapshotBlock) -
            proposal_.tally.yes -
            proposal_.tally.abstain;

        // The code below implements the formula of the
        // early execution support criterion explained in the top of this file.
        // `(1 - supportThreshold) * N_yes > supportThreshold *  N_no,worst-case`
        return
            (RATIO_BASE - proposal_.parameters.supportThreshold) * proposal_.tally.yes >
            proposal_.parameters.supportThreshold * noVotesWorstCase;
    }

    /// @inheritdoc IMajorityVoting
    function isMinParticipationReached(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The code below implements the formula of the
        // participation criterion explained in the top of this file.
        // `N_yes + N_no + N_abstain >= minVotingPower = minParticipation * N_total`
        return
            proposal_.tally.yes + proposal_.tally.no + proposal_.tally.abstain >=
            proposal_.parameters.minVotingPower;
    }

    /// @inheritdoc IMajorityVoting
    function isMinApprovalReached(uint256 _proposalId) public view virtual returns (bool) {
        return proposals[_proposalId].tally.yes >= proposals[_proposalId].minApprovalPower;
    }

    /// @inheritdoc IMajorityVoting
    function minApproval() public view virtual returns (uint256) {
        return minApprovals;
    }

    /// @inheritdoc IMajorityVoting
    function supportThreshold() public view virtual returns (uint32) {
        return votingSettings.supportThreshold;
    }

    /// @inheritdoc IMajorityVoting
    function minParticipation() public view virtual returns (uint32) {
        return votingSettings.minParticipation;
    }

    /// @notice Returns the minimum duration parameter stored in the voting settings.
    /// @return The minimum duration parameter.
    function minDuration() public view virtual returns (uint64) {
        return votingSettings.minDuration;
    }

    /// @notice Returns the minimum voting power required to create a proposal stored in the voting settings.
    /// @return The minimum voting power required to create a proposal.
    function minProposerVotingPower() public view virtual returns (uint256) {
        return votingSettings.minProposerVotingPower;
    }

    /// @notice Returns the vote mode stored in the voting settings.
    /// @return The vote mode parameter.
    function votingMode() public view virtual returns (VotingMode) {
        return votingSettings.votingMode;
    }

    /// @notice Returns the total voting power checkpointed for a specific block number.
    /// @param _blockNumber The block number.
    /// @return The total voting power.
    function totalVotingPower(uint256 _blockNumber) public view virtual returns (uint256);

    /// @notice Returns all information for a proposal by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return parameters The parameters of the proposal.
    /// @return tally The current tally of the proposal.
    /// @return actions The actions to be executed to the `target` contract address.
    /// @return allowFailureMap The bit map representations of which actions are allowed to revert so tx still succeeds.
    /// @return targetConfig Execution configuration, applied to the proposal when it was created. Added in build 3.
    function getProposal(
        uint256 _proposalId
    )
        public
        view
        virtual
        returns (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            Tally memory tally,
            Action[] memory actions,
            uint256 allowFailureMap,
            TargetConfig memory targetConfig
        )
    {
        Proposal storage proposal_ = proposals[_proposalId];

        open = _isProposalOpen(proposal_);
        executed = proposal_.executed;
        parameters = proposal_.parameters;
        tally = proposal_.tally;
        actions = proposal_.actions;
        allowFailureMap = proposal_.allowFailureMap;
        targetConfig = proposal_.targetConfig;
    }

    /// @notice Updates the voting settings.
    /// @dev Requires the `UPDATE_VOTING_SETTINGS_PERMISSION_ID` permission.
    /// @param _votingSettings The new voting settings.
    function updateVotingSettings(
        VotingSettings calldata _votingSettings
    ) external virtual auth(UPDATE_VOTING_SETTINGS_PERMISSION_ID) {
        _updateVotingSettings(_votingSettings);
    }

    /// @notice Updates the minimal approval value.
    /// @dev Requires the `UPDATE_VOTING_SETTINGS_PERMISSION_ID` permission.
    /// @param _minApprovals The new minimal approval value.
    function updateMinApprovals(
        uint256 _minApprovals
    ) external virtual auth(UPDATE_VOTING_SETTINGS_PERMISSION_ID) {
        _updateMinApprovals(_minApprovals);
    }

    /// @notice Creates a new majority voting proposal.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _allowFailureMap Allows proposal to succeed even if an action reverts.
    ///     Uses bitmap representation.
    ///     If the bit at index `x` is 1, the tx succeeds even if the action at `x` failed.
    ///     Passing 0 will be treated as atomic execution.
    /// @param _startDate The start date of the proposal vote.
    ///     If 0, the current timestamp is used and the vote starts immediately.
    /// @param _endDate The end date of the proposal vote.
    ///     If 0, `_startDate + minDuration` is used.
    /// @param _voteOption The chosen vote option to be casted on proposal creation.
    /// @param _tryEarlyExecution If `true`,  early execution is tried after the vote cast.
    ///     The call does not revert if early execution is not possible.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate,
        VoteOption _voteOption,
        bool _tryEarlyExecution
    ) external virtual returns (uint256 proposalId);

    /// @notice Internal function to cast a vote. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    /// @param _voteOption The chosen vote option to be casted on the proposal vote.
    /// @param _voter The address of the account that is voting on the `_proposalId`.
    /// @param _tryEarlyExecution If `true`,  early execution is tried after the vote cast.
    ///     The call does not revert if early execution is not possible.
    function _vote(
        uint256 _proposalId,
        VoteOption _voteOption,
        address _voter,
        bool _tryEarlyExecution
    ) internal virtual;

    /// @notice Internal function to execute a proposal. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    function _execute(uint256 _proposalId) internal virtual {
        Proposal storage proposal_ = proposals[_proposalId];

        proposal_.executed = true;

        _execute(
            proposal_.targetConfig.target,
            bytes32(_proposalId),
            proposal_.actions,
            proposal_.allowFailureMap,
            proposal_.targetConfig.operation
        );

        emit ProposalExecuted(_proposalId);
    }

    /// @notice Internal function to check if a voter can vote. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The address of the voter to check.
    /// @param _voteOption Whether the voter abstains, supports or opposes the proposal.
    /// @return Returns `true` if the given voter can vote on a certain proposal and `false` otherwise.
    function _canVote(
        uint256 _proposalId,
        address _account,
        VoteOption _voteOption
    ) internal view virtual returns (bool);

    /// @notice An internal function that checks if the proposal succeeded or not.
    /// @param _proposalId The ID of the proposal.
    /// @param _isOpen Weather the proposal is open or not.
    /// @return Returns `true` if the proposal succeeded depending on the thresholds and voting modes.
    function _hasSucceeded(uint256 _proposalId, bool _isOpen) internal view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        if (_isOpen) {
            // If the proposal is still open and the voting mode is VoteReplacement,
            // success cannot be determined until the voting period ends.
            if (proposal_.parameters.votingMode == VotingMode.VoteReplacement) {
                return false;
            }

            // For Standard and EarlyExecution modes, check if the support threshold
            // has been reached early to determine success while proposal is still open.
            if (!isSupportThresholdReachedEarly(_proposalId)) {
                return false;
            }
        } else {
            // When the proposal is closed, check if the support threshold
            // has been reached based on final voting results.
            if (!isSupportThresholdReached(_proposalId)) {
                return false;
            }
        }
        if (!isMinParticipationReached(_proposalId)) {
            return false;
        }
        if (!isMinApprovalReached(_proposalId)) {
            return false;
        }

        return true;
    }

    /// @notice Internal function to check if a proposal can be executed. It assumes the queried proposal exists.
    /// @dev Threshold and minimal values are compared with `>` and `>=` comparators, respectively.
    /// @param _proposalId The ID of the proposal.
    /// @return True if the proposal can be executed, false otherwise.
    function _canExecute(uint256 _proposalId) internal view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // Verify that the vote has not been executed already.
        if (proposal_.executed) {
            return false;
        }

        bool isProposalOpen = _isProposalOpen(proposal_);

        // For Standard and VoteReplacement modes, enforce waiting until end date
        if (proposal_.parameters.votingMode != VotingMode.EarlyExecution && isProposalOpen) {
            return false;
        }

        return _hasSucceeded(_proposalId, isProposalOpen);
    }

    /// @notice Internal function to check if a proposal is still open.
    /// @param proposal_ The proposal struct.
    /// @return True if the proposal is open, false otherwise.
    function _isProposalOpen(Proposal storage proposal_) internal view virtual returns (bool) {
        uint64 currentTime = block.timestamp.toUint64();

        return
            proposal_.parameters.startDate <= currentTime &&
            currentTime < proposal_.parameters.endDate &&
            !proposal_.executed;
    }

    /// @notice Internal function to update the plugin-wide proposal settings.
    /// @param _votingSettings The voting settings to be validated and updated.
    function _updateVotingSettings(VotingSettings calldata _votingSettings) internal virtual {
        // Require the support threshold value to be in the interval [0, 10^6-1],
        // because `>` comparison is used in the support criterion and >100% could never be reached.
        if (_votingSettings.supportThreshold > RATIO_BASE - 1) {
            revert RatioOutOfBounds({
                limit: RATIO_BASE - 1,
                actual: _votingSettings.supportThreshold
            });
        }

        // Require the minimum participation value to be in the interval [0, 10^6],
        // because `>=` comparison is used in the participation criterion.
        if (_votingSettings.minParticipation > RATIO_BASE) {
            revert RatioOutOfBounds({limit: RATIO_BASE, actual: _votingSettings.minParticipation});
        }

        if (_votingSettings.minDuration < 60 minutes) {
            revert MinDurationOutOfBounds({limit: 60 minutes, actual: _votingSettings.minDuration});
        }

        if (_votingSettings.minDuration > 365 days) {
            revert MinDurationOutOfBounds({limit: 365 days, actual: _votingSettings.minDuration});
        }

        votingSettings = _votingSettings;

        emit VotingSettingsUpdated({
            votingMode: _votingSettings.votingMode,
            supportThreshold: _votingSettings.supportThreshold,
            minParticipation: _votingSettings.minParticipation,
            minDuration: _votingSettings.minDuration,
            minProposerVotingPower: _votingSettings.minProposerVotingPower
        });
    }

    /// @notice Checks if proposal exists or not.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if proposal exists, otherwise false.
    function _proposalExists(uint256 _proposalId) private view returns (bool) {
        return proposals[_proposalId].parameters.snapshotBlock != 0;
    }

    /// @notice Internal function to update minimal approval value.
    /// @param _minApprovals The new minimal approval value.
    function _updateMinApprovals(uint256 _minApprovals) internal virtual {
        // Require the minimum approval value to be in the interval [0, 10^6],
        // because `>=` comparison is used in the participation criterion.
        if (_minApprovals > RATIO_BASE) {
            revert RatioOutOfBounds({limit: RATIO_BASE, actual: _minApprovals});
        }

        minApprovals = _minApprovals;
        emit VotingMinApprovalUpdated(_minApprovals);
    }

    /// @notice Validates and returns the proposal dates.
    /// @param _start The start date of the proposal.
    ///     If 0, the current timestamp is used and the vote starts immediately.
    /// @param _end The end date of the proposal. If 0, `_start + minDuration` is used.
    /// @return startDate The validated start date of the proposal.
    /// @return endDate The validated end date of the proposal.
    function _validateProposalDates(
        uint64 _start,
        uint64 _end
    ) internal view virtual returns (uint64 startDate, uint64 endDate) {
        uint64 currentTimestamp = block.timestamp.toUint64();

        if (_start == 0) {
            startDate = currentTimestamp;
        } else {
            startDate = _start;

            if (startDate < currentTimestamp) {
                revert DateOutOfBounds({limit: currentTimestamp, actual: startDate});
            }
        }
        // Since `minDuration` is limited to 1 year,
        // `startDate + minDuration` can only overflow if the `startDate` is after `type(uint64).max - minDuration`.
        // In this case, the proposal creation will revert and another date can be picked.
        uint64 earliestEndDate = startDate + votingSettings.minDuration;

        if (_end == 0) {
            endDate = earliestEndDate;
        } else {
            endDate = _end;

            if (endDate < earliestEndDate) {
                revert DateOutOfBounds({limit: earliestEndDate, actual: endDate});
            }
        }
    }

    /// @notice This empty reserved space is put in place to allow future versions to add
    /// new variables without shifting down storage in the inheritance chain
    /// (see [OpenZeppelin's guide about storage gaps]
    /// (https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[46] private __gap;
}
