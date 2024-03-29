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