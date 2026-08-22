const path = require("path");

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== "win32") return;
  const { rcedit } = await import("rcedit");
  const appInfo = context.packager.appInfo;
  const executableName = `${appInfo.productFilename}.exe`;
  await rcedit(path.join(context.appOutDir, executableName), {
    icon: path.join(context.packager.projectDir, "build", "icon.ico"),
    "file-version": appInfo.version,
    "product-version": appInfo.version,
    "version-string": {
      CompanyName: "Luke McLaughlin",
      FileDescription: "Universal on-device file converter for Windows 11",
      InternalName: appInfo.productFilename,
      OriginalFilename: executableName,
      ProductName: appInfo.productName,
    },
  });
};
