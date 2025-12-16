################################################################################
#
# llama-cpp
#
################################################################################

LLAMA_CPP_VERSION = 2995341730f18deb64faa4538bda113328fd791f
LLAMA_CPP_SITE = https://github.com/ggerganov/llama.cpp.git
LLAMA_CPP_SITE_METHOD = git
LLAMA_CPP_GIT_SUBMODULES = YES
LLAMA_CPP_LICENSE = MIT
LLAMA_CPP_LICENSE_FILES = LICENSE

LLAMA_CPP_DEPENDENCIES = host-cmake

LLAMA_CPP_SUPPORTS_IN_SOURCE_BUILD = NO

LLAMA_CPP_CONF_OPTS = \
	-DGGML_NATIVE=OFF \
	-DGGML_OPENMP=OFF \
	-DGGML_ACCELERATE=OFF \
	-DGGML_METAL=OFF \
	-DGGML_VULKAN=OFF \
	-DLLAMA_CURL=OFF \
	-DLLAMA_BUILD_TESTS=OFF \
	-DCMAKE_CXX_FLAGS="$(TARGET_CXXFLAGS) -I$(@D)/tools/mtmd" \
	-DLLAMA_BUILD_CLI=ON \
	-DLLAMA_BUILD_LLAMACPP_CLI=ON \
	-DLLAMA_BUILD_EXAMPLES=ON \
	-DLLAMA_BUILD_SERVER=ON

define LLAMA_CPP_BUILD_CMDS
	# Build an interactive CLI (prefer llama-cli, else llama) plus llama-run.
	set -e; \
	if $(TARGET_MAKE_ENV) $(BR2_CMAKE) --build $(LLAMA_CPP_BUILDDIR) --target llama-cli -- -j$(PARALLEL_JOBS); then \
		:; \
	elif $(TARGET_MAKE_ENV) $(BR2_CMAKE) --build $(LLAMA_CPP_BUILDDIR) --target llama -- -j$(PARALLEL_JOBS); then \
		:; \
	else \
		echo "llama-cpp: failed to build interactive CLI (llama-cli/llama)" >&2; \
		exit 1; \
	fi; \
	$(TARGET_MAKE_ENV) $(BR2_CMAKE) --build $(LLAMA_CPP_BUILDDIR) --target llama-run -- -j$(PARALLEL_JOBS)
endef

define LLAMA_CPP_INSTALL_TARGET_CMDS
	set -e; \
	out="$(LLAMA_CPP_BUILDDIR)/bin"; \
	found=0; \
	cli_path=""; \
	for name in llama-cli llama main; do \
		if [ -x "$$out/$$name" ]; then \
			cli_path="$$out/$$name"; \
			break; \
		fi; \
	done; \
	if [ -z "$$cli_path" ]; then \
		for name in llama-cli llama main; do \
			cand="$$(find "$(LLAMA_CPP_BUILDDIR)" -maxdepth 4 -type f -name "$$name" -print -quit 2>/dev/null)"; \
			if [ -n "$$cand" ] && [ -x "$$cand" ]; then \
				cli_path="$$cand"; \
				break; \
			fi; \
		done; \
	fi; \
	if [ -n "$$cli_path" ]; then \
		case "$$(basename "$$cli_path")" in \
			llama-cli) \
				install -D -m 0755 "$$cli_path" "$(TARGET_DIR)/usr/bin/llama-cli"; \
				;; \
			llama) \
				install -D -m 0755 "$$cli_path" "$(TARGET_DIR)/usr/bin/llama"; \
				;; \
			main) \
				install -D -m 0755 "$$cli_path" "$(TARGET_DIR)/usr/bin/llama"; \
				;; \
		esac; \
		found=1; \
	fi; \
	if [ -x "$$out/llama-run" ]; then \
		install -D -m 0755 "$$out/llama-run" "$(TARGET_DIR)/usr/bin/llama-run"; \
	else \
		echo "llama-cpp: warning: llama-run not found in $$out" >&2; \
	fi; \
	if [ "$$found" -eq 0 ]; then \
		echo "llama-cpp: interactive CLI not found (llama-cli/llama/main)" >&2; \
		ls -la "$$out" >&2 || true; \
		exit 1; \
	fi
endef

$(eval $(cmake-package))
