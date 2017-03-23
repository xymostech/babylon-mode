const fs = require("fs");
const babylon = require("babylon");

const f = fs.readFileSync(process.argv[2], "utf8");
const result = babylon.parse(f, {
    sourceType: "module",
    plugins: ["jsx", "flow", "objectRestSpread", "classProperties"],
});
fs.writeFileSync(
    "/tmp/babylon-parse.json",
    JSON.stringify(result, null, 2));
