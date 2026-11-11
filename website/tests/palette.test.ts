import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import stylelint from "stylelint";
import config from "../.stylelintrc.json" with { type: "json" };

test("accepts black and white text, surfaces, and focus states", async (): Promise<void> => {
	const code =
		"a { color: black; background-color: white; } a:focus-visible { outline-color: currentColor; outline-style: solid; outline-width: 3px; }";
	const result = await stylelint.lint({ code, config });
	assert.equal(result.errored, false);
});

const prohibited: readonly string[] = [
	"color: gray",
	"color: #808080",
	"background-color: rgb(0 0 0 / 50%)",
	"background-image: linear-gradient(black, white)",
	"box-shadow: 1px 1px black",
	"text-shadow: 1px 1px black",
	"opacity: 0.5",
	"filter: blur(2px)",
	"backdrop-filter: blur(2px)",
	"mix-blend-mode: screen",
	"background-blend-mode: multiply",
	"--surface: gray",
	"color: var(--surface)",
	"background: gray",
	"border: 1px solid gray",
	"outline: 1px solid gray",
	"fill: gray",
	"stroke: gray",
];

for (const declaration of prohibited) {
	test(`refuses ${declaration}`, async (): Promise<void> => {
		const result = await stylelint.lint({
			code: `a { ${declaration}; }`,
			config,
		});
		assert.equal(result.errored, true);
	});
}

test("the shipped stylesheet satisfies the palette contract", async (): Promise<void> => {
	const code = await readFile(
		new URL("../dist/styles.css", import.meta.url),
		"utf8",
	);
	const result = await stylelint.lint({ code, config });
	assert.equal(
		result.errored,
		false,
		JSON.stringify(result.results.map((result) => result.warnings)),
	);
});
