// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ZeussToken is ERC20, Ownable { 
    constructor() ERC20("ZeussToken", "ZEUSS") Ownable(0x2cc312F73F34BcdADa7d7589CB3074c7Dc06ebE9) {  
        _mint(0x2cc312F73F34BcdADa7d7589CB3074c7Dc06ebE9, 100000000000000000000000000000);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function transferFromContract(address _to,uint256 amount) external onlyOwner {
        require(amount > 0 , "Amount must be greater than 0");
        _transfer(address(this),_to,amount);
    }

    function burn( uint256 amount) public   {
        _burn(msg.sender, amount);
    }
}