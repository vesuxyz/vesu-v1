import { setup } from "../lib";

const deployer = await setup("sepolia");

const [extensionPO, extensionCL] = await deployer.deployExtensions(
  deployer.config.protocol.singleton!,
  deployer.config.protocol.pragma,
);

console.log("ExtensionPO: ", extensionPO.address);
console.log("ExtensionCL: ", extensionCL.address);
