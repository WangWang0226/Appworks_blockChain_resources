// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "hardhat/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract SimpleSwap is ISimpleSwap, ERC20("SimpleSwap", "SSwap") {
    address private _tokenA;
    address private _tokenB;
    //reserve 要自己計算，不能直接用 balanceOf(address(this)) 取得，避免有人亂轉錢進來，影響 LP token 計算公式
    uint256 private _reserveA;
    uint256 private _reserveB;

    constructor(address token0, address token1) {
        require(token0 != address(0), "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(token1 != address(0), "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(token0 != token1, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");

        _tokenA = uint160(token0) < uint160(token1) ? token0 : token1;
        _tokenB = uint160(token0) < uint160(token1) ? token1 : token0;    
        
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external override returns (uint256) {
        require(tokenIn == address(_tokenA) || tokenIn == address(_tokenB), "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == address(_tokenA) || tokenOut == address(_tokenB), "SimpleSwap: INVALID_TOKEN_OUT");
        require(amountIn != 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");

        uint256 actualAmountIn = doTransferIn(tokenIn, amountIn);

        //always remember mul first before div. 
        //solidity 裡面沒有浮點數，除完結果都會捨去小數點，若結果介於 0~0.99 捨去小數點就會變成 0，這時再怎麼乘都是 0。
        uint256 amountOut = tokenIn == _tokenA
            ? _reserveB * actualAmountIn / (_reserveA + actualAmountIn)
            : _reserveA * actualAmountIn / (_reserveB + actualAmountIn);
        // or this way:
        // uint amountOut = tokenIn == address(_tokenA) 
        //    ? _reserveB - _reserveA * _reserveB / (_reserveA + actualAmountIn)
        //    : _reserveA - _reserveA * _reserveB / (_reserveB + actualAmountIn);
        require(amountOut != 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");

        //state update first, then do transaction to avoid reentrance
        if (tokenIn == address(_tokenA)) {
            _reserveA += actualAmountIn;
            _reserveB -= amountOut;
        } else {
            _reserveB += actualAmountIn;
            _reserveA -= amountOut;
        }

        require(ERC20(tokenOut).transfer(msg.sender, amountOut), "transfer failed");

        emit Swap(msg.sender, tokenIn, tokenOut, actualAmountIn, amountOut);

        return amountOut;
    }

    function addLiquidity(uint256 amountAIn, uint256 amountBIn)
        external
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amountAIn != 0 && amountBIn != 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        uint256 actualAmountAIn;
        uint256 actualAmountBIn;
        uint256 liquidity;
        uint256 totalSupply = totalSupply();

        if (totalSupply == 0) {
            actualAmountAIn = doTransferIn(_tokenA, amountAIn);
            actualAmountBIn = doTransferIn(_tokenB, amountBIn);
            liquidity = Math.sqrt(actualAmountAIn * actualAmountBIn);
        } else {
            uint _actualAmountAIn = Math.min(amountAIn, amountBIn * _reserveA / _reserveB);
            uint _actualAmountBIn = Math.min(amountBIn, amountAIn * _reserveB / _reserveA);
            
            actualAmountAIn = doTransferIn(_tokenA, _actualAmountAIn);
            actualAmountBIn = doTransferIn(_tokenB, _actualAmountBIn);

            liquidity = Math.min(
                (actualAmountAIn * totalSupply) / _reserveA,
                (actualAmountBIn * totalSupply) / _reserveB
            );
            // or this way:
            // liquidity = Math.sqrt(actualAmountAIn * actualAmountBIn);
        }

        _reserveA += actualAmountAIn;
        _reserveB += actualAmountBIn;
        _mint(msg.sender, liquidity);
        emit AddLiquidity(msg.sender, actualAmountAIn, actualAmountBIn, liquidity);
        return (actualAmountAIn, actualAmountBIn, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external override returns (uint256, uint256) {
        require(liquidity != 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        uint amountA = liquidity * _reserveA / totalSupply();
        uint amountB = liquidity * _reserveB / totalSupply();

        _reserveA -= amountA;
        _reserveB -= amountB;
        
        _transfer(msg.sender, address(this), liquidity);
        _burn(address(this), liquidity);
        ERC20(_tokenA).transfer(msg.sender, amountA);
        ERC20(_tokenB).transfer(msg.sender, amountB);

        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);

        return (amountA, amountB);
    }

    function getReserves() external view override returns (uint256, uint256) {
        return (_reserveA, _reserveB);
    }

    function getTokenA() external view override returns (address tokenA) {
        tokenA = _tokenA;
    }

    function getTokenB() external view override returns (address tokenB) {
        tokenB = _tokenB;
    }

    function doTransferIn(address tokenIn, uint256 amountIn) public returns (uint256) {
        uint256 balance = ERC20(tokenIn).balanceOf(address(this));
        require(ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "transfer is failed");
        return ERC20(tokenIn).balanceOf(address(this)) - balance;
    }
}
