pragma solidity >=0.4.8;

// 거래 로그 계약 선언
contract TransactionLogOK {
    // 저장소 정의
    mapping (bytes32 => mapping (bytes32 => string)) public tranlog;

    // 거래 내용 등록
    function setTransaction(bytes32 user_id, bytes32 project_id, string memory tran_data) public {
        // 이미 등록된 경우 예외 처리
        if(bytes(tranlog[user_id][project_id]).length != 0) {
            revert("이미 등록됨");
        }

        // 등록
        tranlog[user_id][project_id] = tran_data;
    }

    // 사용자, 프로젝트별 거래 내용을 가져온다
    function getTransaction(bytes32 user_id, bytes32 project_id) public view returns (string memory tran_data) {
        return tranlog[user_id][project_id];
    }
}