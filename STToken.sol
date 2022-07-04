// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0 <0.9.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract STToken is ERC20, Ownable, Pausable  {
    using SafeMath for uint256;

    event Buy(address indexed investor, uint256 amountUSD, uint256 amountST);
    event UnHold(address indexed investor, uint256 amount);
    event Stake(address indexed investor, uint256 amount, uint256 months);
    event UnStake(address indexed investor, uint256 amount);
    event Dividends(address indexed investor, uint256 amount);

    uint256 private _presaleStartTime  = 0;
    IERC20  private _usd;
    address private _usdWallet         = address(0);
    address private _investStake;
    uint256 private _presalePrice      = 100;                   //1 ST = $1;

    uint256 constant _maxTokens          = 20000000 * (10 ** 18);
    uint256 constant _maxInitPresale     =  2000000 * (10 ** 18);
    uint256 constant _maxTeamPresale     =   500000 * (10 ** 18);
    uint256 constant _maxBuyPresale      =  4000000 * (10 ** 18);
    uint256 constant _maxInvest          =  5000000 * (10 ** 18);
    uint256 constant _maxPancake         =  4500000 * (10 ** 18);
    uint256 constant _maxDividends       =  4000000 * (10 ** 18);
    uint256 constant _maxPresalePeriod   = 180 days;
    uint256 constant _pancakeStartPeriod = 90 days;

    uint256 constant _unStakePenalty   = 2;

    uint256 constant _stakePercent6    = 5;
    uint256 constant _stakePercent12   = 6;
    uint256 constant _stakePercent24   = 7;

    uint256 private _curInitPresale = 0;
    uint256 private _curTeamPresale = 0;
    uint256 private _curBuyPresale  = 0;
    uint256 private _curInvest      = 0;
    uint256 private _curPancake     = 0;
    uint256 private _curDividends   = 0;
    uint256 private _curBurned      = 0;
    uint256 private _curHolded      = 0;
    uint256 private _curStaked      = 0;

    struct HoldStruct {
        uint256 amount;
        uint256 withdrawedAmount;
        bool    isTeam;
    }
    mapping(address => HoldStruct) public holds;

    struct StakeStruct {
        uint256 amount;
        uint256 startedTime;
        uint256 stakePeriod;
        uint256 withdrawedDividends;
        uint256 lastWithdrawedTime;
    }
    mapping(address => StakeStruct) public stakes;

    //==============================================================================
    constructor () ERC20('SUPREME TRUTH', 'ST') {
        _mint(address(this), _maxTokens);
    }

    function init(uint256 startPresaleTime, IERC20 usdAddr, address usdWallet, address investStakeAddr) public onlyOwner {
        _presaleStartTime = startPresaleTime;
        _usd              = usdAddr;
        _usdWallet        = usdWallet;
        _investStake      = investStakeAddr;
    }

    //==============================================================================
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    //==============================================================================
    function burn(uint256 amount) public onlyOwner {
        _curBurned += amount;
        _burn(address(this), amount);
    }

    //==============================================================================
    function mintInit(address to, uint256 amount) public onlyOwner {
        require(_presaleStartTime != 0, "MintInit: Contract does not inited");
        require(to != address(0), "Invalid address");
        require(amount > 0, "Invalid amount");
        require(block.timestamp > _presaleStartTime, "MintInit: Presale not was started");
        require(block.timestamp < (_presaleStartTime+_maxPresalePeriod), "MintInit: Presale period is gone");

        require((_curInitPresale+amount) <= _maxInitPresale, "MintInit: Limit expired");
        _curInitPresale += amount;
        _curHolded += amount;

        if (holds[to].amount == 0) {
            holds[to] = HoldStruct(amount, 0, false);
        } else {
            require(holds[to].isTeam == false, "MintTeam: Already holded as team");
            holds[to].amount += amount;
        }
    }

    //==============================================================================
    function mintTeam(address to, uint256 amount) public onlyOwner {
        require(_presaleStartTime != 0, "MintTeam: Contract does not inited");
        require(to != address(0), "Invalid address");
        require(amount > 0, "Invalid amount");
        require(block.timestamp > _presaleStartTime, "MintTeam: Presale not was started");
        require(block.timestamp < (_presaleStartTime+_maxPresalePeriod), "MintTeam: Presale period is gone");

        require((_curTeamPresale+amount) <= _maxTeamPresale, "MintTeam: Limit expired");
        _curTeamPresale += amount;
        _curHolded += amount;

        if (holds[to].amount == 0) {
            holds[to] = HoldStruct(amount, 0, true);
        } else {
            require(holds[to].isTeam == true, "MintTeam: Already holded as investor");
            holds[to].amount += amount;
        }
    }

    //==============================================================================
    function mintInvest(uint256 amount) public onlyOwner {
        require(_presaleStartTime != 0, "MintInvest: Contract does not inited");
        require(amount > 0, "Invalid amount");
        require(_investStake != address(0), "MintInvest: Contract does not inited");
        require((balanceOf(_investStake)+amount) <= _maxInvest, "MintInvest: Limit expired");

        require((_curInvest+amount) <= _maxInvest, "MintInvest: Limit expired");
        _curInvest += amount;

        _transfer(address(this),_investStake, amount);
    }

    //==============================================================================
    function mintPancake(address to, uint256 amount) public onlyOwner {
        require(_presaleStartTime != 0, "MintPancake: Contract does not inited");
        require(to != address(0), "Invalid address");
        require(amount > 0, "Invalid amount");
        require(block.timestamp > (_presaleStartTime+_pancakeStartPeriod), "MintPancake: Pancake not was started");

        require((_curPancake+amount) <= _maxPancake, "MintPancake: Limit expired");
        _curPancake += amount;

        _transfer(address(this), to, amount);
    }

    //==============================================================================
    function buy(uint256 amountUSD) public whenNotPaused {
        require(_presaleStartTime != 0, "Buy: Contract does not inited");
        require(amountUSD > 0, "Invalid amount");
        require(_usdWallet != address(0), "Buy: Contract does not inited");
        require(block.timestamp > _presaleStartTime, "Buy: Presale not was started");
        require(block.timestamp < (_presaleStartTime+_maxPresalePeriod), "Buy: Presale period is gone");

        uint256 amountST = (100 * amountUSD) / _presalePrice;
        require((_curBuyPresale+amountST) <= _maxBuyPresale, "Buy: Limit expired");

        _usd.transferFrom(msg.sender, address(this), amountUSD);
        _usd.transfer(_usdWallet, amountUSD);

        _curBuyPresale += amountST;
        _curHolded += amountST;

        if (holds[msg.sender].amount == 0) {
            holds[msg.sender] = HoldStruct(amountST, 0, false);
        } else {
            require(holds[msg.sender].isTeam == false, "MintTeam: Already holded as team");
            holds[msg.sender].amount += amountST;
        }

        emit Buy(msg.sender, amountUSD, amountST);
    }

    function setCurrentPrice(uint256 price) public onlyOwner {
        _presalePrice = (100*price)/1 ether;
    }

    function getCurrentPrice() public view returns (uint256) {
        return (1 ether * _presalePrice) / 100;
    }

    //==============================================================================
    function getHoldOf(address investor) public view returns(HoldStruct memory) {
        return holds[investor];
    }

    function unhold() public whenNotPaused {
        require(holds[msg.sender].amount > 0, "UnHold: Not holded");

        uint256 fullMonths = 0;
        if (block.timestamp > _presaleStartTime) {
            fullMonths = (block.timestamp - _presaleStartTime) / 30 days;
        }

        uint256 fullUnHolded = 0;
        if (holds[msg.sender].isTeam) {
            if (fullMonths >= 24) {
                fullUnHolded = holds[msg.sender].amount;
            } else
            if (fullMonths >= 12) {
                fullUnHolded = (50 * holds[msg.sender].amount) / 100;
            }
        } else {
            if (fullMonths >= 18) {
                fullUnHolded = holds[msg.sender].amount;
            } else
            if (fullMonths >= 15) {
                fullUnHolded = (75 * holds[msg.sender].amount) / 100;
            } else
            if (fullMonths >= 12) {
                fullUnHolded = (50 * holds[msg.sender].amount) / 100;
            } else
            if (fullMonths >= 9) {
                fullUnHolded = (25 * holds[msg.sender].amount) / 100;
            }
        }

        require(fullUnHolded > holds[msg.sender].withdrawedAmount, "UnHold: All possible tokens are already unholded");
        uint256 unHoldAmount = fullUnHolded - holds[msg.sender].withdrawedAmount;

        holds[msg.sender].withdrawedAmount += unHoldAmount;
        _transfer(address(this), msg.sender, unHoldAmount);
        _curHolded -= unHoldAmount;

        emit UnHold(msg.sender, unHoldAmount);
    }

    //==============================================================================
    function getTotalOfInit() public view returns (uint256) {
        return _curInitPresale;
    }

    function getTotalOfTeam() public view returns (uint256) {
        return _curTeamPresale;
    }

    function getTotalOfBuy() public view returns (uint256) {
        return _curBuyPresale;
    }

    function getTotalOfInvest() public view returns (uint256) {
        return _curInvest;
    }

    function getTotalOfPancake() public view returns (uint256) {
        return _curPancake;
    }

    function getTotalOfDividends() public view returns (uint256) {
        return _curDividends;
    }

    function getTotalOfBurned() public view returns (uint256) {
        return _curBurned;
    }

    function getTotalOfHolded() public view returns (uint256) {
        return _curHolded;
    }

    function getTotalOfStaked() public view returns (uint256) {
        return _curStaked;
    }

    function getPresaleStartTime() public view returns (uint256) {
        return _presaleStartTime;
    }

    //==============================================================================
    function stake(uint256 amount, uint256 months) public whenNotPaused {
        require(stakes[msg.sender].amount == 0, "Stake: Already staked");
        require(amount > 0, "Invalid amount");
        require((months==6)||(months==12)||(months==24), "Stake: Invalid months value - allow only 6,12,24");

        _transfer(msg.sender, address(this), amount);
        stakes[msg.sender] = StakeStruct(amount, block.timestamp, months, 0, block.timestamp);
        _curStaked += amount;

        emit Stake(msg.sender, amount, months);
    }

    function getStakeOf(address investor) public view returns(StakeStruct memory) {
        return stakes[investor];
    }

    function _calcAllDividends(uint256 amount, uint256 startedTime, uint256 months) internal view returns (uint256) {
        uint256 stakePercent = 0;
        if (months == 6) {
            stakePercent = _stakePercent6;
        } else
        if (months == 12) {
            stakePercent = _stakePercent12;
        } else
        if (months == 24) {
            stakePercent = _stakePercent24;
        }

        uint256 fullMonths = 0;
        if (block.timestamp > startedTime) {
            fullMonths = (block.timestamp - startedTime) / 30 days;
        }
        if (fullMonths > months) {
            fullMonths = months;
        }

        uint256 fullDividends = (fullMonths * stakePercent * amount) / 100;
        return fullDividends;
    }

    function unstake() public whenNotPaused {
        require(stakes[msg.sender].amount > 0, "UnStake: Not staked");

        uint256 amount;
        uint256 penalty = 0;
        if (block.timestamp > (stakes[msg.sender].startedTime + (30 days * stakes[msg.sender].stakePeriod))) {
            amount = stakes[msg.sender].amount;
        } else {
            amount = ((100-_unStakePenalty) * stakes[msg.sender].amount) / 100;
            penalty = stakes[msg.sender].amount - amount;
        }
        _curStaked -= stakes[msg.sender].amount;

        uint256 dividends = _calcAllDividends(stakes[msg.sender].amount,
                                              stakes[msg.sender].startedTime,
                                              stakes[msg.sender].stakePeriod);
        if (dividends <= stakes[msg.sender].withdrawedDividends) {
            dividends = 0;
        } else {
            dividends -= stakes[msg.sender].withdrawedDividends;
        }

        if ((_curDividends+dividends) > _maxDividends) {
            dividends = _maxDividends - _curDividends;
        }
        _curDividends += dividends;

        _transfer(address(this), msg.sender, amount+dividends);
        if (penalty > 0) {
            _curBurned += penalty;
            _burn(address(this), penalty);
        }
        delete stakes[msg.sender];

        emit UnStake(msg.sender, amount);
        emit Dividends(msg.sender, dividends);
    }

    function getDividends() public whenNotPaused {
        require(stakes[msg.sender].amount > 0, "UnStake: Not staked");
        require(block.timestamp > (stakes[msg.sender].lastWithdrawedTime + 30 days), "GetDividends: Can not receive dividends more than once per month");

        uint256 dividends = _calcAllDividends(stakes[msg.sender].amount,
                                              stakes[msg.sender].startedTime,
                                              stakes[msg.sender].stakePeriod);
        require(dividends > 0, "GetDividends: Calced dividends value is zero");
        require(dividends > stakes[msg.sender].withdrawedDividends, "GetDividends: All dividends already paid");
        dividends -= stakes[msg.sender].withdrawedDividends;
        require(dividends >= 10 * (10 ** 18), "GetDividends: Minimal dividends value is 10ST");

        if ((_curDividends+dividends) > _maxDividends) {
            dividends = _maxDividends - _curDividends;
            require(dividends > 0, "GetDividends: Limit expired");
        }
        _curDividends += dividends;

        stakes[msg.sender].withdrawedDividends += dividends;
        stakes[msg.sender].lastWithdrawedTime = block.timestamp;
        _transfer(address(this), msg.sender, dividends);

        emit Dividends(msg.sender, dividends);
    }
}