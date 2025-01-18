export const fivefivefivelauncherAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "_factory",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_router",
        "type": "address",
        "internalType": "address payable"
      },
      {
        "name": "_feeCollector",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_ponder",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_priceOracle",
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
    "name": "BASIS_POINTS",
    "inputs": [],
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
    "name": "CONTRIBUTOR_PERCENT",
    "inputs": [],
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
    "name": "CREATOR_PERCENT",
    "inputs": [],
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
    "name": "KUB_TO_MEME_KUB_LP",
    "inputs": [],
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
    "name": "KUB_TO_MEME_PONDER_LP",
    "inputs": [],
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
    "name": "KUB_TO_PONDER_KUB_LP",
    "inputs": [],
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
    "name": "LAUNCH_DURATION",
    "inputs": [],
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
    "name": "LP_LOCK_PERIOD",
    "inputs": [],
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
    "name": "LP_PERCENT",
    "inputs": [],
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
    "name": "MAX_PONDER_PERCENT",
    "inputs": [],
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
    "name": "MIN_KUB_CONTRIBUTION",
    "inputs": [],
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
    "name": "MIN_PONDER_CONTRIBUTION",
    "inputs": [],
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
    "name": "MIN_POOL_LIQUIDITY",
    "inputs": [],
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
    "name": "PONDER_TO_BURN",
    "inputs": [],
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
    "name": "PONDER_TO_MEME_PONDER",
    "inputs": [],
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
    "name": "PRICE_STALENESS_THRESHOLD",
    "inputs": [],
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
    "name": "TARGET_RAISE",
    "inputs": [],
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
    "name": "cancelLaunch",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "claimRefund",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "contributeKUB",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "contributePONDER",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "createLaunch",
    "inputs": [
      {
        "name": "params",
        "type": "tuple",
        "internalType": "struct FiveFiveFiveLauncher.LaunchParams",
        "components": [
          {
            "name": "name",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "symbol",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "imageURI",
            "type": "string",
            "internalType": "string"
          }
        ]
      }
    ],
    "outputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "factory",
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
    "name": "feeCollector",
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
    "name": "getContributionInfo",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "kubCollected",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "ponderCollected",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "ponderValueCollected",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "totalValue",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getContributorInfo",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "contributor",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "kubContributed",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "ponderContributed",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "ponderValue",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "tokensReceived",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getLaunchInfo",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "tokenAddress",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "name",
        "type": "string",
        "internalType": "string"
      },
      {
        "name": "symbol",
        "type": "string",
        "internalType": "string"
      },
      {
        "name": "imageURI",
        "type": "string",
        "internalType": "string"
      },
      {
        "name": "kubRaised",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "launched",
        "type": "bool",
        "internalType": "bool"
      },
      {
        "name": "lpUnlockTime",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getMinimumRequirements",
    "inputs": [],
    "outputs": [
      {
        "name": "minKub",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "minPonder",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "minPoolLiquidity",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "getPoolInfo",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "memeKubPair",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "memePonderPair",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "hasSecondaryPool",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getRemainingToRaise",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "remainingTotal",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "remainingPonderValue",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "launchCount",
    "inputs": [],
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
    "name": "launches",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "base",
        "type": "tuple",
        "internalType": "struct FiveFiveFiveLauncher.LaunchBaseInfo",
        "components": [
          {
            "name": "tokenAddress",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "name",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "symbol",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "imageURI",
            "type": "string",
            "internalType": "string"
          },
          {
            "name": "launched",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "creator",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "lpUnlockTime",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "launchDeadline",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "cancelled",
            "type": "bool",
            "internalType": "bool"
          },
          {
            "name": "isFinalizingLaunch",
            "type": "bool",
            "internalType": "bool"
          }
        ]
      },
      {
        "name": "contributions",
        "type": "tuple",
        "internalType": "struct FiveFiveFiveLauncher.ContributionState",
        "components": [
          {
            "name": "kubCollected",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "ponderCollected",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "ponderValueCollected",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "tokensDistributed",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      },
      {
        "name": "allocation",
        "type": "tuple",
        "internalType": "struct FiveFiveFiveLauncher.TokenAllocation",
        "components": [
          {
            "name": "tokensForContributors",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "tokensForLP",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      },
      {
        "name": "pools",
        "type": "tuple",
        "internalType": "struct FiveFiveFiveLauncher.PoolInfo",
        "components": [
          {
            "name": "memeKubPair",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "memePonderPair",
            "type": "address",
            "internalType": "address"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "owner",
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
    "name": "ponder",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract PonderToken"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "priceOracle",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract PonderPriceOracle"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "router",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IPonderRouter"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "usedNames",
    "inputs": [
      {
        "name": "",
        "type": "string",
        "internalType": "string"
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
    "name": "usedSymbols",
    "inputs": [
      {
        "name": "",
        "type": "string",
        "internalType": "string"
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
    "name": "withdrawLP",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "DualPoolsCreated",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "memeKubPair",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "memePonderPair",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "kubLiquidity",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "ponderLiquidity",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "KUBContributed",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "contributor",
        "type": "address",
        "indexed": false,
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
    "name": "LPTokensWithdrawn",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "creator",
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
    "name": "LaunchCancelled",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "creator",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "kubCollected",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "ponderCollected",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "LaunchCompleted",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "kubRaised",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "ponderRaised",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "LaunchCreated",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "token",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "creator",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "imageURI",
        "type": "string",
        "indexed": false,
        "internalType": "string"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PonderBurned",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
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
    "name": "PonderContributed",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "contributor",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "kubValue",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PonderPoolSkipped",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "ponderAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "ponderValueInKub",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "RefundProcessed",
    "inputs": [
      {
        "name": "user",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "kubAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "ponderAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "tokenAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TokensDistributed",
    "inputs": [
      {
        "name": "launchId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
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
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "AlreadyLaunched",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ContributionFailed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ContributionTooSmall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "EthTransferFailed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ExcessiveContribution",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ExcessivePonderContribution",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ExcessivePriceDeviation",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ImageRequired",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientLPTokens",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientLiquidity",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientPoolLiquidity",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InsufficientPriceHistory",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidAmount",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidPayment",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidTokenParams",
    "inputs": []
  },
  {
    "type": "error",
    "name": "LPStillLocked",
    "inputs": []
  },
  {
    "type": "error",
    "name": "LaunchBeingFinalized",
    "inputs": []
  },
  {
    "type": "error",
    "name": "LaunchDeadlinePassed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "LaunchDoesNotExist",
    "inputs": []
  },
  {
    "type": "error",
    "name": "LaunchExpired",
    "inputs": []
  },
  {
    "type": "error",
    "name": "LaunchNotCancellable",
    "inputs": []
  },
  {
    "type": "error",
    "name": "LaunchNotFound",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NoContributionToRefund",
    "inputs": []
  },
  {
    "type": "error",
    "name": "PoolCreationFailed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "PriceOutOfBounds",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ReentrancyGuardReentrantCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "RefundFailed",
    "inputs": []
  },
  {
    "type": "error",
    "name": "StalePrice",
    "inputs": []
  },
  {
    "type": "error",
    "name": "TokenNameExists",
    "inputs": []
  },
  {
    "type": "error",
    "name": "TokenSymbolExists",
    "inputs": []
  },
  {
    "type": "error",
    "name": "Unauthorized",
    "inputs": []
  }
] as const;
