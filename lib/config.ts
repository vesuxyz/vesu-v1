import { isArray, mapValues } from "lodash-es";
import { BigNumberish, uint256 } from "starknet";
import { AssetIndexes, CreatePoolParams, i257, u256 } from ".";

export const SCALE = 10n ** 18n;
export const PERCENT = 10n ** 16n;
export const FRACTION = 10n ** 13n;
export const YEAR_IN_SECONDS = 360 * 24 * 60 * 60;

interface ProtocolConfig {
  singleton: string | undefined;
  extension: string | undefined;
  oracle: string | undefined;
}

export class EnvAssetParams {
  constructor(
    public name: string,
    public symbol: string,
    public decimals: bigint,
    public mint: bigint,
    public pragmaKey: BigNumberish,
    public price: bigint,
    public isLegacy: boolean,
    public feeRate: bigint,
    public v_token_name: string,
    public v_token_symbol: string,
    public address: string | undefined = undefined,
  ) {}

  get scale() {
    return 10n ** this.decimals;
  }

  erc20Params() {
    const { name, symbol, decimals } = this;
    return { name, symbol, decimals, initial_supply: toU256(this.mint * this.scale) };
  }
}

export interface PoolConfig {
  id: bigint;
  description: string;
  type: string;
  params: CreatePoolParams;
}

export interface Config {
  name: string;
  protocol: ProtocolConfig;
  env?: EnvAssetParams[];
  pools: Record<string, PoolConfig>;
}

export function toU256(x: BigNumberish): u256 {
  return uint256.bnToUint256(x.toString());
}

export function toI257(x: BigNumberish): i257 {
  x = BigInt(x);
  if (x < 0n) {
    return { abs: -x, is_negative: true };
  }
  return { abs: x, is_negative: false };
}

export function logAddresses(label: string, records: Record<string, any>) {
  records = mapValues(records, stringifyAddresses);
  console.log(label, records);
}

function stringifyAddresses(value: any): any {
  if (isArray(value)) {
    return value.map(stringifyAddresses);
  }
  return value?.address ? value.address : value;
}

export function mapAssetPairs<T>(
  assets: EnvAssetParams[],
  callback: (collateral: EnvAssetParams, debt: EnvAssetParams, indexes: AssetIndexes) => T | undefined,
) {
  return assets
    .flatMap((collateral, collateral_asset_index) =>
      assets.map((debt, debt_asset_index) => {
        return callback(collateral, debt, { collateral_asset_index, debt_asset_index });
      }),
    )
    .filter(Boolean) as T[];
}

export function toUtilizationScale(value: number) {
  return BigInt(Math.trunc(value * 100000));
}

export function toScale(value: number) {
  return BigInt(Math.trunc(value * Number(SCALE)));
}

export function toAddress(value: BigInt) {
  return ("0x" + value.toString(16)).toLowerCase();
}
