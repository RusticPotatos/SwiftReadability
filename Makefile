.PHONY: develop test docs

DOCS_DIR := .build/docs

develop:
	@git stash
	@git checkout develop
	@git stash pop

test:
	swift test

docs:
	@mkdir -p $(DOCS_DIR)
	swift package --allow-writing-to-directory $(DOCS_DIR) \
		generate-documentation --target SwiftReadability --output-path $(DOCS_DIR)
