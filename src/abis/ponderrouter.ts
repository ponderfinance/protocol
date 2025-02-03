export const ponderrouterAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "_factory",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_weth",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_kkubUnwrapper",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "receive",
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "FACTORY",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IPonderFactory"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "KKUB_UNWRAPPER",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address payable"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "WETH",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "addLiquidity",
    "inputs": [
      {
        "name": "tokenA",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "tokenB",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "amountADesired",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountBDesired",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountAMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountBMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amountA",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountB",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "liquidity",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "addLiquidityETH",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "amountTokenDesired",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountTokenMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountETHMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amountToken",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountETH",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "liquidity",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "getAmountsIn",
    "inputs": [
      {
        "name": "amountOut",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      }
    ],
    "outputs": [
      {
        "name": "amounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getAmountsOut",
    "inputs": [
      {
        "name": "amountIn",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      }
    ],
    "outputs": [
      {
        "name": "amounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getReserves",
    "inputs": [
      {
        "name": "tokenA",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "tokenB",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "reserveA",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "reserveB",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "quote",
    "inputs": [
      {
        "name": "amountA",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "reserveA",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "reserveB",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amountB",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "removeLiquidity",
    "inputs": [
      {
        "name": "tokenA",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "tokenB",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "liquidity",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountAMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountBMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amountA",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountB",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "removeLiquidityETH",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "liquidity",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountTokenMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountETHMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amountToken",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountETH",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "removeLiquidityETHSupportingFeeOnTransferTokens",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "liquidity",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountTokenMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountETHMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amountETH",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "swapETHForExactTokens",
    "inputs": [
      {
        "name": "amountOut",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "swapExactETHForTokens",
    "inputs": [
      {
        "name": "amountOutMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "swapExactETHForTokensSupportingFeeOnTransferTokens",
    "inputs": [
      {
        "name": "amountOutMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "swapExactTokensForETH",
    "inputs": [
      {
        "name": "amountIn",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountOutMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "swapExactTokensForETHSupportingFeeOnTransferTokens",
    "inputs": [
      {
        "name": "amountIn",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountOutMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "swapExactTokensForTokens",
    "inputs": [
      {
        "name": "amountIn",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountOutMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "swapExactTokensForTokensSupportingFeeOnTransferTokens",
    "inputs": [
      {
        "name": "amountIn",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountOutMin",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "swapTokensForExactETH",
    "inputs": [
      {
        "name": "amountOut",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountInMax",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "swapTokensForExactTokens",
    "inputs": [
      {
        "name": "amountOut",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amountInMax",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "internalType": "address[]"
      },
      {
        "name": "to",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "weth",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "ETHRefundFailed",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "reason",
        "type": "bytes",
        "indexed": false,
        "internalType": "bytes"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "ETHRefunded",
    "inputs": [
      {
        "name": "to",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "LiquidityETHAdded",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "to",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amountToken",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "amountETH",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "liquidity",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PriceImpactWarning",
    "inputs": [
      {
        "name": "inputAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "outputAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "priceImpact",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "SwapETHForExactTokens",
    "inputs": [
      {
        "name": "sender",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "ethAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "tokenAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "path",
        "type": "address[]",
        "indexed": false,
        "internalType": "address[]"
      },
      {
        "name": "to",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "SwapETHForExactTokensStarted",
    "inputs": [
      {
        "name": "sender",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "ethValue",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "expectedOutput",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "deadline",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "AddressEmptyCode",
    "inputs": [
      {
        "name": "target",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "AddressInsufficientBalance",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "ApprovalFailed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ETHTransferFailed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ExcessiveInputAmount",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ExpiredDeadline",
    "inputs": []
  },
  {
    "type": "error",
    "name": "FailedInnerCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "IdenticalAddresses",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientAAmount",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientAmount",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientBAmount",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientETH",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientInputAmount",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientLiquidity",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientOutputAmount",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidAmount",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidPath",
    "inputs": []
  },
  {
    "type": "error",
    "name": "PairCreationFailed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ReentrancyGuardReentrantCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "SafeERC20FailedOperation",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "TransferFailed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "UnwrapFailed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ZeroAddress",
    "inputs": []
  }
] as const;
