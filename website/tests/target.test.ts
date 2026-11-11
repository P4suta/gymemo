import assert from "node:assert/strict";
import { test } from "node:test";
import { websiteTarget } from "../playwright.config.ts";

test("the default target uses the isolated local server", () => {
	assert.deepEqual(websiteTarget(undefined), {
		production: false,
		baseURL: "http://127.0.0.1:4174",
	});
});

test("production acceptance uses the public HTTPS domain", () => {
	assert.deepEqual(websiteTarget("production"), {
		production: true,
		baseURL: "https://gymemo.yasunobu.dev",
	});
});

test("misspelled targets and supplied URLs cannot fall back to a local test", () => {
	for (const value of [
		"",
		"prod",
		"Production",
		" production",
		"https://example.com",
	]) {
		assert.throws(() => websiteTarget(value), /must be unset or production/);
	}
});
