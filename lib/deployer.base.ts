import fs from "fs";
import { DeclareContractPayload, ec, encode, json } from "starknet";

import { Account, Calldata, CompiledContract, Contract, hash, RpcProvider } from "starknet";

export class BaseDeployer extends Account {
  constructor(
    public provider: RpcProvider,
    { address, signer }: Account,
    private alreadyDeclared: Record<string, string> = {},
  ) {
    super(provider, address, signer);
  }

  async loadContract(contractAddress: string) {
    const { abi } = await this.getClassAt(contractAddress);
    return new Contract(abi, contractAddress, this.provider);
  }

  async declareCached(name: string) {
    if (this.alreadyDeclared[name]) {
      return this.alreadyDeclared[name];
    }
    const { transaction_hash, class_hash } = await this.declareIfNot(readArtifacts(name));
    if (transaction_hash != undefined && transaction_hash.length > 0) {
      await this.waitForTransaction(transaction_hash);
    }
    this.alreadyDeclared[name] = class_hash;
    return class_hash;
  }

  async declareCachedWithPayload(name: string, payload: DeclareContractPayload) {
    if (this.alreadyDeclared[name]) {
      return this.alreadyDeclared[name];
    }
    const { transaction_hash, class_hash } = await this.declareIfNot(payload);
    if (transaction_hash != undefined && transaction_hash.length > 0) {
      await this.waitForTransaction(transaction_hash);
    }
    this.alreadyDeclared[name] = class_hash;
    return class_hash;
  }

  async deferContract(name: string, constructorCalldata: Calldata = []) {
    const payload = readArtifacts(name);
    const classHash = await this.declareCachedWithPayload(name, payload);
    const salt = randomHex(); // use "0" for deterministic address
    const contractAddress = hash.calculateContractAddressFromHash(salt, classHash, constructorCalldata, 0);
    const { abi } = payload.contract as CompiledContract;
    const contract = new Contract(abi, contractAddress, this.provider);
    const calls = this.buildUDCContractPayload({ classHash, salt, constructorCalldata, unique: false });
    return [contract, calls] as const;
  }
}

function readArtifacts(contract: string): DeclareContractPayload {
  return {
    contract: readArtifact(`./target/release/vesu_${contract}.contract_class.json`),
    casm: readArtifact(`./target/release/vesu_${contract}.compiled_contract_class.json`),
  };
}

function readArtifact(path: string) {
  return json.parse(fs.readFileSync(path).toString("ascii"));
}

export function randomHex() {
  return `0x${encode.buf2hex(ec.starkCurve.utils.randomPrivateKey())}`;
}
