export const ponderpriceoracleAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "_factory",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_baseToken",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_stablecoin",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "BASE_TOKEN",
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
    "name": "FACTORY",
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
    "name": "STABLECOIN",
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
    "name": "baseToken",
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
    "name": "consult",
    "inputs": [
      {
        "name": "pair",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "tokenIn",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "amountIn",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "period",
        "type": "uint32",
        "internalType": "uint32"
      }
    ],
    "outputs": [
      {
        "name": "amountOut",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "factory",
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
    "name": "getCurrentPrice",
    "inputs": [
      {
        "name": "pair",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "tokenIn",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "amountIn",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amountOut",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getPriceInStablecoin",
    "inputs": [
      {
        "name": "tokenIn",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "amountIn",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amountOut",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "initializePair",
    "inputs": [
      {
        "name": "pair",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "isPairInitialized",
    "inputs": [
      {
        "name": "pair",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "lastUpdateTime",
    "inputs": [
      {
        "name": "pair",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "observationLength",
    "inputs": [
      {
        "name": "pair",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "observations",
    "inputs": [
      {
        "name": "pair",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "index",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "timestamp",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "price0Cumulative",
        "type": "uint224",
        "internalType": "uint224"
      },
      {
        "name": "price1Cumulative",
        "type": "uint224",
        "internalType": "uint224"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "stableCoin",
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
    "name": "update",
    "inputs": [
      {
        "name": "pair",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "OracleUpdated",
    "inputs": [
      {
        "name": "pair",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "price0Cumulative",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "price1Cumulative",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "blockTimestamp",
        "type": "uint32",
        "indexed": false,
        "internalType": "uint32"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PairInitialized",
    "inputs": [
      {
        "name": "pair",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "timestamp",
        "type": "uint32",
        "indexed": false,
        "internalType": "uint32"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "AlreadyInitialized",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ElapsedTimeZero",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientData",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidPair",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidPeriod",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidTimeElapsed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidToken",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotInitialized",
    "inputs": []
  },
  {
    "type": "error",
    "name": "StalePrice",
    "inputs": []
  },
  {
    "type": "error",
    "name": "UpdateTooFrequent",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ZeroAddress",
    "inputs": []
  }
] as const;
