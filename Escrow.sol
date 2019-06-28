pragma solidity >=0.4.8;

//소유자 관리용 계약
contract Owned{
    // 상태변수
    address public owner; // 소유자 주소

    // 소유자 변경 시 이벤트
    event TransferOwnership(address oldaddr, address newaddr);

    // 소유자 한정 메서드용 수식자
    modifier onlyOwner() {if(msg.sender != owner ) revert("Only owner allowed"); _;}

    // 생성자
    constructor () public{
        owner = msg.sender; // 처음에 계약을 생성한 주소를소유자로 한다
    }

    // 소유자 변경
    function transferOwnership(address _new) public onlyOwner {
        address oldaddr = owner;
        owner = _new;
        emit TransferOwnership(oldaddr, owner);
    }
}

// 회원 관리용 계약
contract Members is Owned {
    // 상태 변수 선언
    address public coin; // 토큰(가상 화폐) 주소
    MemberStatus[] public status; // 회원 등급 배열
    mapping(address => History) public tradingHistory;  // 회원별 거래 이력

    // 회원 등급용 구조체
    struct MemberStatus {
        string name; // 등급명
        uint256 times; //최저 거래 횟수
        uint256 sum; // 최저 거래 금액
        int8 rate; // 캐시백 비율
    }
    // 거래 이력용 구조체
    struct History {
        uint256 times; // 거래 횟수
        uint256 sum; // 거래 금액
        uint256 statusIndex; // 등급 인덱스
    }

    // 토큰 한정 메서드용 수식자
    modifier onlyCoin() {if(msg.sender == coin) _;}

    //토큰 주소 설정
    function setCoin(address _addr) public onlyOwner{
        coin = _addr;
    }

    //회원 등급 추가
    function pushStatus(string memory _name, uint256 _times, uint256 _sum, int8 _rate) public onlyOwner{
        status.push(MemberStatus({
            name: _name,
            times: _times,
            sum: _sum,
            rate: _rate
        }));
    }

    //회원 등급 내용 변경
    function editStatus(uint256 _index, string memory _name, uint256 _times, uint256 _sum, int8 _rate) public onlyOwner{
        if(_index < status.length) {
            status[_index].name = _name;
            status[_index].times = _times;
            status[_index].sum = _sum;
            status[_index].rate = _rate;
        }
    }

    // 거래 내역 갱신
    function updateHistory(address _member, uint256 _value) public onlyCoin {
        tradingHistory[_member].times += 1;
        tradingHistory[_member].sum += _value;
        //새로운 회원 등급 결정(거래마다 실행)
        uint256 index;
        int8 tmprate;
        for(uint i = 0; i < status.length; i++){
            //최저 거래 횟수, 최저 거래 금액 충족 시 가장 캐시백 비율이 좋은 등급으로 설정
            if(tradingHistory[_member].times >= status[i].times &&
               tradingHistory[_member].sum >= status[i].sum &&
               tmprate < status[i].rate){
               index = i;
            }
        }
        tradingHistory[_member].statusIndex = index;
    }

    // 캐시백 비율 획득(회원의 등급에 해당하는 비율확인)
    function getCashbackRate(address _member) public view returns (int8 rate){
        rate = status[tradingHistory[_member].statusIndex].rate;
    }
}

// 회원 관리 기능이 구현된 가상 화폐
contract OreOreCoin is Owned{
    // 상태 변수 선언
    string public name; // 토큰 이름
    string public symbol; // 토큰 단위
    uint8 public decimals; // 소수점 이하 자릿수
    uint256 public totalSupply; // 토큰 총량
    mapping (address => uint256) public balanceOf; // 각 주소의 잔고
    mapping (address => int8) public blackList; // 블랙 리스트
    mapping (address => Members) public members; // 각 주소의 회원 정보

    // 이벤트 알림
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Blacklisted(address indexed target);
    event DeleteFromBlacklist(address indexed target);
    event RejectedPaymentToBlacklistedAddr(address indexed from, address indexed to, uint256 value);
    event RejectedPaymentFromBlacklistedAddr(address indexed from, address indexed to, uint256 value);
    event Cashback(address indexed from, address indexed to, uint256 value);

    // 생성자
    constructor(uint256 _supply, string memory _name, string memory _symbol, uint8 _decimals) public{
        balanceOf[msg.sender] = _supply;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _supply;
    }

    // 주소를 블랙리스트에 등록
    function blacklisting(address _addr) public onlyOwner {
        blackList[_addr] = 1;
        emit Blacklisted(_addr);
    }

    // 주소를 블랙리스트에서 제거
    function deleteFromBlacklist(address _addr) public onlyOwner {
        blackList[_addr] = -1;
        emit DeleteFromBlacklist(_addr);
    }

    // 회원 관리 계약 설정
    function setMembers(Members _members) public {
        members[msg.sender] = Members(_members);
    }

    // 송금
    function transfer(address _to, uint256 _value) public {
        // 부정 송금 확인
        if (balanceOf[msg.sender] < _value) revert("error");
        if (balanceOf[_to] + _value < balanceOf[_to]) revert("error");

        // 블랙리스트에 존재하는 주소는 입출금 불가
        if (blackList[msg.sender] > 0) {
            emit RejectedPaymentFromBlacklistedAddr(msg.sender, _to, _value);
        } else if (blackList[_to] > 0) {
            emit RejectedPaymentToBlacklistedAddr(msg.sender, _to, _value);
        } else {
            //캐시백 금액 계산 (각 대상의 캐시백 비율을 사용)
            uint256 cashback = 0;
            if(address(members[_to]) > address(0)){
                cashback = _value / 100 * uint256(members[_to].getCashbackRate(msg.sender));
                members[_to].updateHistory(msg.sender, _value);
            }
            
            // 송금하는 주소와 송금받는 주소의 잔고 갱신
            balanceOf[msg.sender] -= (_value - cashback);
            balanceOf[_to] += (_value - cashback);

            // 이벤트 알림
            emit Transfer(msg.sender, _to, _value);
            emit Cashback(_to, msg.sender, cashback);
        }
    }
}

// 크라우드 세일
contract Crowdsale is Owned {
    // 상태 변수
    uint256 public fundingGoal; // 목표 금액
    uint256 public deadline; // 기한
    uint256 public price; // 토큰 기본 가격
    uint256 public transferableToken; // 전송 가능 토큰
    uint256 public soldToken; // 판매된 토큰
    uint256 public startTime; // 개시 시간
    OreOreCoin public tokenReward; // 지불에 사용할 토큰
    bool public fundingGoalReached; // 목표 도달 플래그
    bool public isOpened; // 크라우드 세일 개시 플래그
    mapping (address => Property) public fundersProperty; // 자금 제공자의 자산 정보

    // 자산 정보 구조체
    struct Property {
        uint256 paymentEther; // 지불한 Ether
        uint256 reservedToken; // 받은 토큰
        bool withdrawed; // 인출 플래그
    }

    // 이벤트 알림
    event CrowdsaleStart(uint fundingGoal, uint deadline, uint transferableToken, address beneficiary);
    event ReservedToken(address backer, uint amount, uint token);
    event CheckGoalReached(address beneficiary, uint fundingGoal, uint amountRaised, bool reached, uint raisedToken);
    event WithdrawalToken(address addr, uint amount, bool result);
    event WithdrawalEther(address addr, uint amount, bool result);

    // 수식자
    modifier afterDeadline() { if(now >= deadline) revert("기한 지남"); _; }

    // 생성자
    constructor (uint _fundignGoalInEthers,
                 uint _transferableToken,
                 uint _amountOfTokenPerEther,
                 OreOreCoin _addressOfTokenUsedAsReward) public {
        fundingGoal = _fundignGoalInEthers * 1 ether;
        price = 1 ether / _amountOfTokenPerEther;
        transferableToken = _transferableToken;
        tokenReward = OreOreCoin(_addressOfTokenUsedAsReward);
    }

    // 이름 없는 함수(Ether 받기)
    function () external payable {
        // 개시 전 또는 기간이 지난 경우 예외 처리
        if (!isOpened || now >= deadline) revert("기한 지남");

        // 받은 Ether와 판매 예정 토큰
        uint amount = msg.value;
        uint token = amount / price * (100 + currentSwapRate()) / 100;

        // 판매 예정 토큰의 확인(예정 수를 초과하는 경우는 예외 처리)
        if (token == 0 || soldToken + token > transferableToken) revert("예정 수 초과");
        // 자산 제공자의 자산 정보 변경
        fundersProperty[msg.sender].paymentEther += amount;
        fundersProperty[msg.sender].reservedToken += token;
        soldToken += token;
        emit ReservedToken(msg.sender, amount, token);
    }

    // 개시(토큰이 예정한 수 이상 있다면 개시)
    function start(uint _durationInMinutes) public onlyOwner {
        if (fundingGoal == 0 || price == 0 || transferableToken == 0 ||
            address(tokenReward) == address(0) || _durationInMinutes == 0 || startTime != 0) revert("토큰 없음");
        if (tokenReward.balanceOf(address(this)) >= transferableToken) {
            startTime = now;
            deadline = now + _durationInMinutes * 1 minutes;
            isOpened = true;
            emit CrowdsaleStart(fundingGoal, deadline, transferableToken, owner);
        }
    }

    // 교환 비율(개시 시작부터 시간이 적게 경과할수록 더 많은 보상)
    function currentSwapRate() public view returns(uint) {
        if(startTime + 3 minutes > now) {
            return 100;
        } else if (startTime + 5 minutes > now) {
            return 50;
        } else if ( startTime + 10 minutes > now) {
            return 20;
        } else {
            return 0;
        }
    }

    // 남은 시간(분 단위)과 목표와의 차이(eth 단위), 토큰 확인용 메서드
    function getRemainingTimeEthToken() public view returns(uint min, uint shortage, uint remainToken) {
        if(now < deadline) {
            min = (deadline - now) / (1 minutes);
        }
        shortage = (fundingGoal - address(this).balance) / (1 ether);
        remainToken = transferableToken - soldToken;
    }

    // 목표 도달 확인(기한 후 실시 가능)
    function checkGoalReached() public afterDeadline {
        if (isOpened) {
            // 모인 Ether와 목표 Ether 비교
            if(address(this).balance >= fundingGoal) {
                fundingGoalReached = true;
            }
            isOpened = false;
            emit CheckGoalReached(owner, fundingGoal, address(this).balance, fundingGoalReached, soldToken);
        }
    }

    // 소유자용 인출 메서드(판매 종료 후 실시 가능)
    function withdrawalOwner() public onlyOwner {
        if (isOpened) revert("크라우드 세일");

        // 목표 달성: Ether와 남은 토큰. 목표 미달: 토큰
        if (fundingGoalReached) {
        // Ether
            uint amount = address(this).balance;
            if (amount > 0) {
                bool ok = msg.sender.send(amount);
                emit WithdrawalEther(msg.sender, amount, ok);
            }
            // 남은 토큰
            uint val = transferableToken - soldToken;
            if (val > 0) {
                tokenReward.transfer(msg.sender, transferableToken - soldToken);
                emit WithdrawalToken(msg.sender, val, true);
            }
        } else {
            // 토큰
            uint val2 = tokenReward.balanceOf(address(this));
            tokenReward.transfer(msg.sender, val2);
            emit WithdrawalToken(msg.sender, val2, true);
        }
    }

    // 자금 제공자용 인출 메서드(세일 종료 후 실시 가능)
    function withdrawal () public {
        if (isOpened) return;
        // 이미 인출된 경우 예외 처리
        if (fundersProperty[msg.sender].withdrawed) revert("이미 인출됨");
        // 목표 달성: 토큰, 목표 미달: Ether
        if (fundingGoalReached) {
            if (fundersProperty[msg.sender].reservedToken > 0) {
                tokenReward.transfer(msg.sender, fundersProperty[msg.sender].reservedToken);
                fundersProperty[msg.sender].withdrawed = true;
                emit WithdrawalToken(
                     msg.sender,
                     fundersProperty[msg.sender].reservedToken,
                     fundersProperty[msg.sender].withdrawed
                );
            }
        } else {
            if (fundersProperty[msg.sender].paymentEther > 0) {
                if (msg.sender.send(fundersProperty[msg.sender].paymentEther)) {
                    fundersProperty[msg.sender].withdrawed = true;
                }
                emit WithdrawalEther(
                     msg.sender,
                     fundersProperty[msg.sender].paymentEther,
                     fundersProperty[msg.sender].withdrawed
                );
            }
        }
    }
}

// 에스크로
contract Escrow is Owned {
    // 상태 변수
    OreOreCoin public token; // 토큰
    uint256 public salesVolume; // 판매량
    uint256 public sellingPrice; // 판매 가격
    uint256 public deadline; // 기한
    bool public isOpened; // 에스크로 개시 플래그

    // 이벤트 알림
    event EscrowStart(uint salesVolume, uint sellingPrice, uint deadline, address beneficiary);
    event ConfirmedPayment(address addr, uint amount);

    // 생성자
    constructor (OreOreCoin _token, uint256 _salesVolume, uint256 _priceInEther) public {
        token = OreOreCoin(_token);
        salesVolume = _salesVolume;
        sellingPrice = _priceInEther * 1 ether;
    }

    // 이름 없는 함수(Ether 수령)
    function () external payable {
        // 개시 전 또는 기한이 끝난 경우에는 예외 처리
        if (!isOpened || now >= deadline) revert("기한 끝남");

        // 판매 가격 미만인 경우 예외 처리
        uint amount = msg.value;
        if (amount < sellingPrice) revert("판매 가격 미만");

        // 보내는 사람에게 토큰을 전달하고 에스크로 개시 플래그를 false로 설정
        token.transfer(msg.sender, salesVolume);
        isOpened = false;
        emit ConfirmedPayment(msg.sender, amount);
    }

    // 개시(토큰이 예정 수 이상이라면 게시)
    function start(uint256 _durationInMinutes) public onlyOwner {
        if (address(token) == address(0) || salesVolume == 0 || sellingPrice == 0 || deadline != 0) revert("토큰 예정 수 이상");
        if (token.balanceOf(address(this)) >= salesVolume) {
            deadline = now + _durationInMinutes * 1 minutes;
            isOpened = true;
            emit EscrowStart(salesVolume, sellingPrice, deadline, owner);
        }
    }

    // 남은 시간 확인용 메서드(분 단위)
    function getRemainingTime() public view returns(uint min) {
        if(now < deadline) {
            min = (deadline - now) / (1 minutes);
        }
    }

    // 종료
    function close() public onlyOwner {
        // 토큰을 소유자에게 전송
        token.transfer(owner, token.balanceOf(address(this)));
        // 계약을 파기(해당 계약이 보유하고 있는 Ether는 소유자에게 전송)
        selfdestruct(address(uint160(owner)));
    }
}