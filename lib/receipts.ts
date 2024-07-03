import { GetTransactionReceiptResponse, ProviderInterface, RPC } from "starknet";

export type AcceptedTransactionReceiptResponse = GetTransactionReceiptResponse & { transaction_hash: string };

// this might eventually be solved in starknet.js https://github.com/starknet-io/starknet.js/issues/796
export function isAcceptedTransactionReceiptResponse(
  receipt: GetTransactionReceiptResponse,
): receipt is AcceptedTransactionReceiptResponse {
  return "transaction_hash" in receipt;
}

export function isIncludedTransactionReceiptResponse(receipt: GetTransactionReceiptResponse): receipt is RPC.Receipt {
  return "block_number" in receipt;
}

export function ensureAccepted(receipt: GetTransactionReceiptResponse): AcceptedTransactionReceiptResponse {
  if (!isAcceptedTransactionReceiptResponse(receipt)) {
    throw new Error(`Transaction was rejected: ${JSON.stringify(receipt, null, 2)}`);
  }
  return receipt;
}

export function ensureIncluded(receipt: GetTransactionReceiptResponse): RPC.Receipt {
  const acceptedReceipt = ensureAccepted(receipt);
  if (!isIncludedTransactionReceiptResponse(acceptedReceipt)) {
    throw new Error(`Transaction was not included in a block: ${JSON.stringify(receipt, null, 2)}`);
  }
  return acceptedReceipt;
}

export async function waitForInclusion(transactionHash: string, provider: ProviderInterface): Promise<RPC.Receipt> {
  let receipt;
  for (let i = 0; i < 10; i++) {
    receipt = ensureAccepted(await provider.waitForTransaction(transactionHash));
    if (isIncludedTransactionReceiptResponse(receipt)) {
      console.log("included", i);
      return receipt;
    }
    console.log("waiting", i, transactionHash);
    await sleep(1000);
  }
  throw new Error(`Transaction was not included in a block after 10 tries: ${JSON.stringify(receipt, null, 2)}`);
}

async function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
