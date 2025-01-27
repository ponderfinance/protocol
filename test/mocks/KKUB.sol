// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IAdminAsset {
    function isSuperAdmin(address _addr, string calldata _token) external view returns (bool);
}

interface IKYC {
    function kycsLevel(address _addr) external view returns (uint256);
}

interface IKAP20 {
    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint256 tokens);

    function totalSupply() external view returns (uint256);
    function balanceOf(address tokenOwner) external view returns (uint256 balance);
    function allowance(address tokenOwner, address spender) external view returns (uint256 remaining);
    function transfer(address to, uint256 tokens) external returns (bool success);
    function approve(address spender, uint256 tokens) external returns (bool success);
    function transferFrom(address from, address to, uint256 tokens) external returns (bool success);
    function getOwner() external view returns (address);
    function batchTransfer(address[] calldata _from, address[] calldata _to, uint256[] calldata _value) external returns (bool success);
    function adminTransfer(address _from, address _to, uint256 _value) external returns (bool success);
}

contract KKUB is IKAP20 {
    string public name = "Wrapped KUB";
    string public symbol = "KKUB";
    uint8 public decimals = 18;

    event Deposit(address indexed dst, uint256 value);
    event Withdrawal(address indexed src, uint256 value);
    event Paused(address account);
    event Unpaused(address account);

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowed;
    mapping(address => bool) public blacklist;

    IAdminAsset public admin;
    IKYC public kyc;
    bool public paused;
    uint256 public kycsLevel;

    modifier onlySuperAdmin() {
        require(admin.isSuperAdmin(msg.sender, symbol), "Restricted to super admin");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Pausable: not paused");
        _;
    }

    constructor(address _admin, address _kyc) {
        admin = IAdminAsset(_admin);
        kyc = IKYC(_kyc);
        kycsLevel = 1;
    }

    function setKYC(address _kyc) external onlySuperAdmin {
        kyc = IKYC(_kyc);
    }

    function setKYCsLevel(uint256 _kycsLevel) external onlySuperAdmin {
        require(_kycsLevel > 0, "Invalid KYC level");
        kycsLevel = _kycsLevel;
    }

    function getOwner() external view override returns (address) {
        return address(admin);
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable whenNotPaused {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 _value) public whenNotPaused {
        require(!blacklist[msg.sender], "Address is in the blacklist");
        _withdraw(_value, msg.sender);
    }

    function withdrawAdmin(uint256 _value, address _addr) public onlySuperAdmin {
        _withdraw(_value, _addr);
    }

    function _withdraw(uint256 _value, address _addr) internal {
        require(balances[_addr] >= _value, "Insufficient balance");
        require(kyc.kycsLevel(_addr) > kycsLevel, "KYC verification failed");

        balances[_addr] -= _value;
        payable(_addr).transfer(_value);
        emit Withdrawal(_addr, _value);
        emit Transfer(_addr, address(0), _value);
    }

    function totalSupply() public view override returns (uint256) {
        return address(this).balance;
    }

    function balanceOf(address _addr) public view override returns (uint256) {
        return balances[_addr];
    }

    function allowance(address _owner, address _spender) public view override returns (uint256) {
        return allowed[_owner][_spender];
    }

    function approve(address _spender, uint256 _value) public override whenNotPaused returns (bool) {
        require(!blacklist[msg.sender], "Address is in the blacklist");
        _approve(msg.sender, _spender, _value);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from zero address");
        require(spender != address(0), "Approve to zero address");

        allowed[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transfer(address _to, uint256 _value) public override whenNotPaused returns (bool) {
        require(balances[msg.sender] >= _value, "Insufficient balance");
        require(!blacklist[msg.sender] && !blacklist[_to], "Address is in the blacklist");

        balances[msg.sender] -= _value;
        balances[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public override whenNotPaused returns (bool) {
        require(balances[_from] >= _value, "Insufficient balance");
        require(allowed[_from][msg.sender] >= _value, "Allowance exceeded");
        require(!blacklist[_from] && !blacklist[_to], "Address is in the blacklist");

        balances[_from] -= _value;
        balances[_to] += _value;
        allowed[_from][msg.sender] -= _value;
        emit Transfer(_from, _to, _value);
        return true;
    }

    function batchTransfer(address[] calldata _from, address[] calldata _to, uint256[] calldata _value) external override onlySuperAdmin returns (bool) {
        require(_from.length == _to.length && _to.length == _value.length, "Arrays must be of equal length");
        for (uint256 i = 0; i < _from.length; i++) {
            require(balances[_from[i]] >= _value[i], "Insufficient balance");
            balances[_from[i]] -= _value[i];
            balances[_to[i]] += _value[i];
            emit Transfer(_from[i], _to[i], _value[i]);
        }
        return true;
    }

    function adminTransfer(address _from, address _to, uint256 _value) external override onlySuperAdmin returns (bool) {
        require(balances[_from] >= _value, "Insufficient balance");
        balances[_from] -= _value;
        balances[_to] += _value;
        emit Transfer(_from, _to, _value);
        return true;
    }
}
