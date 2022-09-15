const fs = require("fs");
const babelParser = require("@babel/parser");

const f = fs.readFileSync(process.argv[2], "utf8");

try {
  const result = babelParser.parse(f, {
      sourceType: "module",
      tokens: true,
      plugins: [
          "jsx",
          "flow",
          "objectRestSpread",
          "classProperties",
          "dynamicImport",
          "optionalChaining",
      ],
  });

  const lines = f.split("\n");

  let pointCount = 0;
  const pointCounts = lines.map(line => {
    const oldPointCount = pointCount;
    pointCount += [...line].length + 1;
    return oldPointCount;
  });

  function locToPoint(loc) {
    if (lines[loc.line - 1] == null) {
      return pointCount;
    }
    return pointCounts[loc.line - 1] + [...lines[loc.line - 1].slice(0, loc.column)].length;
  }

  const tokens = result.tokens;
  const tree = result.program.body;

  tokens.forEach(token => {
    if (token.loc) {
      token.start = locToPoint(token.loc.start);
      token.end = locToPoint(token.loc.end);
    }
  });

  function traverse(treeNode) {
    if (!treeNode) {
      return;
    }

    if (treeNode.loc) {
      treeNode.start = locToPoint(treeNode.loc.start);
      treeNode.end = locToPoint(treeNode.loc.end);
    }

    Object.keys(treeNode).forEach(key => {
      if (Array.isArray(treeNode[key])) {
        treeNode[key].forEach(traverse);
      } else if (treeNode[key] && typeof treeNode[key] === "object") {
        traverse(treeNode[key]);
      }
    });
  }
  traverse(tree);

  fs.writeFileSync("/tmp/babylon-parse.json", JSON.stringify(result, null, 2));
} catch (e) {
  fs.writeFileSync("/tmp/babylon-error", e);
  fs.unlinkSync("/tmp/babylon-parse.json");
}
