// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

// 1. Pay and Enter the lottery
// 2. Generate a random number and randomly pick a winner using that random number
//   2.1 -> Use Chainlink VRF2 to pick the random number
// 3. Trigger and pick a winner after sometime or interval
//   3.1 -> Use chainlink Keepers to trigger the pick winner function
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

error Raffle__NotEnoughETHEntered();
error Raffle__NotOpen();
error Raffle__TransferFailed();
error Raffle__UpKeepNotNeeded();

contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface {
    // enums
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint256 private immutable i_entranceFee;
    address payable[] private s_players;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 2;
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_interval;

    // Lottery state
    RaffleState private s_raffleState;
    address private s_recentWinner;

    // events
    event RaffleEnter(address indexed player);
    event RequestID(uint256 indexed requestID);
    event WinnerPicked(address indexed winner);

    constructor(
        address vrfCoordinatorAddress,
        uint256 entranceFee,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        uint256 interval
    ) VRFConsumerBaseV2(vrfCoordinatorAddress) {
        i_entranceFee = entranceFee;
        s_raffleState = RaffleState.OPEN;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorAddress);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
        i_interval = interval;
    }

    /*  
        @dev This functions lets a player in the raffle when they pay the entrance fee
     */
    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughETHEntered();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = (s_players.length > 0);
        bool hasBalance = (address(this).balance > 0);
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");

        if (!upkeepNeeded) {
            revert Raffle__UpKeepNotNeeded();
        }

        uint256 s_requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestID(s_requestId);
    }

    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        s_raffleState = RaffleState.CALCULATING;

        uint256 winnerIndex = randomWords[0] % s_players.length;
        address winner = s_players[winnerIndex];
        s_recentWinner = winner;
        s_players = new address payable[](0);
        s_raffleState = RaffleState.OPEN;

        (bool success, ) = winner.call{value: address(this).balance}("");

        if (!success) {
            revert Raffle__TransferFailed();
        }

        emit WinnerPicked(winner);
    }

    // Pure / view functions
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }
}
