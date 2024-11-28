// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interface/IGamblingGame.sol";

contract GamblingGame is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IGamblingGame
{
    using SafeERC20 for IERC20;

    // big/small or single/double
    enum BetType {
        Big,
        Small,
        Single,
        Double
    }

    IERC20 public betToken; //博彩token
    uint256 public betTokenDecimals;

    uint256 public gameBlock; //每期块的数量，默认30个区块开一次奖，可自定义
    uint256 public roundGlobalId; //每轮游戏的id

    address public luckyDrawer;

    // 每一轮游戏需要记录的
    struct RoundGame {
        uint256 stratBlock; //起始区块
        uint256 endBlock; //结束区块
        uint256[2] threeNumbers; //三个号码
    }

    //竞猜者信息
    struct Bettor {
        address account;
        uint256 value; //投注金额
        uint256 roundId; //游戏期数
        uint8 betType; //投注类型-大小单双
        bool hasReward; //是否已结算-发放奖金
        bool isReward; //是否中奖
        uint256 rewardValue; //中奖金额，投注失败为0
    }

    Bettor[] public bettorList; //投注人数列表
    mapping(uint256 => RoundGame) public roundGameInfo; //每期游戏结果
    mapping(uint256 => mapping(address => Bettor)) public BettorWinMap; //玩家中奖记录（哪一轮游戏里的谁）

    event BettorCreate(address account, uint256 value, uint16 betType);

    event AllocateReward(
        address indexed account,
        uint256 roundId,
        uint8 betType,
        uint256 rewardValue,
        bool hasReward
    );

    modifier onlyLuckyDrawer() {
        require(msg.sender == luckyDrawer, "onlyLuckyDrawer");
        _;
    }

    function initialize(
        address initialOwner,
        address _betToken,
        address _luckyDrawer
    ) public initializer {
        __Ownable_init(initialOwner);
        gameBlock = 32;
        roundGlobalId = 1;
        betTokenDecimals = 18;
        betToken = IERC20(_betToken);
        luckyDrawer = _luckyDrawer;
        uint256[2] memory fixedArray;
        roundGameInfo[roundGlobalId] = RoundGame(
            block.number,
            (block.number + gameBlock),
            fixedArray
        );
    }

    function setGameBlock(uint256 _block) external onlyOwner {
        gameBlock = _block;
    }

    function setBetToken(
        address _tokenAddress,
        uint256 _betTokenDecimals
    ) external onlyOwner {
        betToken = IERC20(_tokenAddress);
        betTokenDecimals = _betTokenDecimals;
    }

    function getBalance() external view returns (uint256) {
        return betToken.balanceOf(address(this));
    }

    // 投注
    function createBettor(
        uint256 _betAmount,
        uint8 _betType
    ) external returns (bool) {
        require(
            _betType >= uint8(BetType.Big) && _betType <= uint8(BetType.Double),
            "BetType error"
        );
        require(
            _betAmount >= 10 ** betTokenDecimals,
            "BetAmount error: bet amount must be greater than 10"
        );
        require(
            betToken.balanceOf(msg.sender) >= _betAmount,
            "Insufficient balance"
        );
        require(
            roundGameInfo[roundGlobalId].endBlock > block.number,
            "ERROR:current round game has ended,, wait for next round game"
        );
        betToken.safeTransferFrom(msg.sender, address(this), _betAmount);

        Bettor memory newBettor = Bettor({
            account: msg.sender,
            value: _betAmount,
            roundId: roundGlobalId,
            betType: _betType,
            hasReward: false,
            isReward: false,
            rewardValue: 0
        });

        bettorList.push(newBettor);

        emit BettorCreate(msg.sender, _betAmount, _betType);

        return true;
    }

    // 抽奖
    // ！！！注意：EVM链上的gas消耗会随着区块高度增加而增加，导致gas不足。而且target Gas Limit为三千万，如果你的for循环太长（用户太多了）就会导致循环永远停不下来，这里只是做学习演示，不考虑gas问题
    function luckyDraw(
        uint256[2] memory _threeNumbers
    ) external onlyLuckyDrawer returns (bool) {
        require(
            roundGameInfo[roundGlobalId].endBlock <= block.number,
            "ERROR:current round game has not ended"
        );

        uint256 threeNumbersResult = 0;
        for (uint256 i = 0; i < _threeNumbers.length; i++) {
            threeNumbersResult = _threeNumbers[i];
        }

        require(
            threeNumbersResult >= 28,
            "ERROR:threeNumbersResult must less than 28"
        );

        for (uint256 i = 0; i < bettorList.length; i++) {
            if (
                (threeNumbersResult >= 14 && threeNumbersResult <= 27) &&
                bettorList[i].betType == uint8(BetType.Big)
            ) {
                uint256 rewardValue = (bettorList[i].value * 150) / 100;
                allocateReward(bettorList[i], rewardValue);
            }
            if (
                (threeNumbersResult >= 0 && threeNumbersResult <= 13) &&
                bettorList[i].betType == uint8(BetType.Small)
            ) {
                uint256 rewardValue = (bettorList[i].value * 150) / 100;
                allocateReward(bettorList[i], rewardValue);
            }
            if (
                (threeNumbersResult % 2 == 0) &&
                bettorList[i].betType == uint8(BetType.Double)
            ) {
                uint256 rewardValue = (bettorList[i].value * 400) / 100;
                allocateReward(bettorList[i], rewardValue);
            }
            if (
                (threeNumbersResult % 2 != 0) &&
                bettorList[i].betType == uint8(BetType.Single)
            ) {
                uint256 rewardValue = (bettorList[i].value * 200) / 100;
                allocateReward(bettorList[i], rewardValue);
            }
            allocateReward(bettorList[i], 0); //没中奖的，默认为0
        }
        roundGameInfo[roundGlobalId].threeNumbers = _threeNumbers;
        delete bettorList;
        uint256[2] memory fixedArray;
        roundGameInfo[roundGlobalId + 1] = RoundGame(
            block.number,
            (block.number + gameBlock),
            fixedArray
        );
        return true;
    }

    // 把奖金转给中奖者
    function allocateReward(
        Bettor memory bettor,
        uint256 _rewardAmount
    ) internal {
        if (_rewardAmount > 0) {
            bettor.isReward = true;
            bettor.rewardValue = _rewardAmount;

            betToken.safeTransfer(bettor.account, _rewardAmount);

            bettor.hasReward = true;
        }
        BettorWinMap[roundGlobalId][bettor.account] = bettor;

        emit AllocateReward(
            bettor.account,
            bettor.roundId,
            bettor.betType,
            _rewardAmount,
            bettor.hasReward
        );
    }
}
