import { BigNumberish, CairoCustomEnum, Uint256 } from "starknet";
import { toI257 } from ".";

export type u256 = Uint256;

export interface i257 {
  abs: bigint;
  is_negative: boolean;
}

interface Amount {
  amount_type: CairoCustomEnum;
  denomination: CairoCustomEnum;
  value: i257;
}

interface UnsignedAmount {
  amount_type: CairoCustomEnum;
  denomination: CairoCustomEnum;
  value: bigint;
}

export interface AssetParams {
  asset: string;
  floor: bigint;
  initial_rate_accumulator: bigint;
  initial_full_utilization_rate: bigint;
  max_utilization: bigint;
  is_legacy: boolean;
  fee_rate: bigint;
}

export interface VTokenParams {
  v_token_name: string;
  v_token_symbol: string;
}

export interface PragmaOracleParams {
  pragma_key: BigNumberish;
  timeout: bigint;
  number_of_sources: bigint;
}

export interface InterestRateConfig {
  min_target_utilization: bigint;
  max_target_utilization: bigint;
  target_utilization: bigint;
  min_full_utilization_rate: bigint;
  max_full_utilization_rate: bigint;
  zero_utilization_rate: bigint;
  rate_half_life: bigint;
  target_rate_percent: bigint;
}

export interface LiquidationParams extends AssetIndexes {
  liquidation_factor: bigint;
}

export interface AssetIndexes {
  collateral_asset_index: number;
  debt_asset_index: number;
}

export interface LTVParams extends AssetIndexes {
  max_ltv: bigint;
}

export interface AssetConfig {
  total_collateral_shares: bigint;
  total_nominal_debt: bigint;
  reserve: bigint;
  max_utilization: bigint;
  floor: bigint;
  scale: bigint;
  is_legacy: boolean;
  last_updated: bigint;
  last_rate_accumulator: bigint;
  last_full_utilization_rate: bigint;
  fee_rate: bigint;
}

export interface ShutdownParams {
  recovery_period: bigint;
  subscription_period: bigint;
  ltv_params: LTVParams[];
}

export interface FeeParams {
  fee_recipient: string;
}

export interface CreatePoolParams {
  asset_params: AssetParams[];
  v_token_params: VTokenParams[];
  ltv_params: LTVParams[];
  interest_rate_configs: InterestRateConfig[];
  pragma_oracle_params: PragmaOracleParams[];
  liquidation_params: LiquidationParams[];
  shutdown_params: ShutdownParams;
  fee_params: FeeParams;
  owner: string;
}

export interface ModifyPositionParams {
  pool_id: bigint;
  collateral_asset: string;
  debt_asset: string;
  user: string;
  collateral: Amount;
  debt: Amount;
  data: any;
}

export interface TransferPositionParams {
  pool_id: bigint;
  from_collateral_asset: string;
  to_collateral_asset: string;
  from_debt_asset: string;
  to_debt_asset: string;
  from_user: string;
  to_user: string;
  collateral: UnsignedAmount;
  debt: UnsignedAmount;
  from_data: any;
  to_data: any;
}

export interface LiquidatePositionParams {
  pool_id: bigint;
  collateral_asset: string;
  debt_asset: string;
  user: string;
  receive_as_shares: boolean;
  data: any;
}

export function Amount(args?: {
  amountType: "Delta" | "Target";
  denomination: "Native" | "Assets";
  value: bigint;
}): Amount {
  if (!args) {
    return {
      amount_type: new CairoCustomEnum({ Delta: {}, Target: undefined }),
      denomination: new CairoCustomEnum({ Native: {}, Assets: undefined }),
      value: toI257(0n),
    };
  }

  const amountTypeEnum: Record<string, any> = { Delta: undefined, Target: undefined };
  amountTypeEnum[args.amountType] = {};

  const denominationEnum: Record<string, any> = { Native: undefined, Assets: undefined };
  denominationEnum[args.denomination] = {};

  return {
    amount_type: new CairoCustomEnum(amountTypeEnum),
    denomination: new CairoCustomEnum(denominationEnum),
    value: toI257(args.value),
  };
}

export function UnsignedAmount(args?: {
  amountType: "Delta" | "Target";
  denomination: "Native" | "Assets";
  value: bigint;
}): UnsignedAmount {
  if (!args) {
    return {
      amount_type: new CairoCustomEnum({ Delta: {}, Target: undefined }),
      denomination: new CairoCustomEnum({ Native: {}, Assets: undefined }),
      value: 0n,
    };
  }

  const amountTypeEnum: Record<string, any> = { Delta: undefined, Target: undefined };
  amountTypeEnum[args.amountType] = {};

  const denominationEnum: Record<string, any> = { Native: undefined, Assets: undefined };
  denominationEnum[args.denomination] = {};

  return {
    amount_type: new CairoCustomEnum(amountTypeEnum),
    denomination: new CairoCustomEnum(denominationEnum),
    value: args.value,
  };
}
