.PHONY: all build build-wasm build-native build-riscv test test-native test-riscv clean submit help runtime

# 变量定义
COMPILER_WASM = target/wasm-gc/release/build/bin/bin.wasm
# Native compiler paths (debug and release)
COMPILER_NATIVE_DEBUG = target/native/debug/build/bin/bin.exe
COMPILER_NATIVE_RELEASE = target/native/release/build/bin/bin.exe
# Keep legacy name pointing to release by default
COMPILER_NATIVE = $(COMPILER_NATIVE_RELEASE)
RUNTIME_LIB = contest-2025-data/riscv_rt/libruntime.a

# 默认目标：构建 native 版本
all: build-native

# 构建所有版本
build: build-wasm build-native

# 构建 wasm-gc 版本（用于提交）
build-wasm:
	@echo "Building MiniMoonBit compiler (wasm-gc)..."
	@cd bin && moon build --target wasm-gc
	@echo "✓ wasm-gc build complete: $(COMPILER_WASM)"

# 构建 native 版本（用于本地开发和测试）
build-native:
	@echo "Building MiniMoonBit compiler (native)..."
	@cd bin && moon build --target native
	@echo "✓ native build complete: $(COMPILER_NATIVE_RELEASE)"

# Build native debug (used by test-file)
build-native-debug:
	@echo "Building MiniMoonBit compiler (native, debug)..."
	@cd bin && moon build --target native --debug
	@echo "✓ native (debug) build complete: $(COMPILER_NATIVE_DEBUG)"

# 构建 RISC-V 运行时库
runtime:
	@echo "Building RISC-V runtime library..."
	@if [ ! -f "$(RUNTIME_LIB)" ]; then \
		cd contest-2025-data/riscv_rt && \
		riscv64-linux-gnu-gcc -c lib.c start.c -O2 -march=rv64gc -mabi=lp64d && \
		riscv64-linux-gnu-ar rcs libruntime.a lib.o start.o && \
		echo "✓ Runtime library built: $(RUNTIME_LIB)"; \
	else \
		echo "✓ Runtime library already exists: $(RUNTIME_LIB)"; \
	fi

# 运行所有测试
test: test-native test-riscv test-official

# 运行 native 测试（编译并执行测试，与答案对比）
test-native: build-native
	@echo ""
	@echo "========================================="
	@echo "Running native tests with execution and answer comparison..."
	@echo "========================================="
	@./test_all_enums.sh

# 运行 RISC-V qemu 测试（完整的端到端测试，与官方答案对比）
test-riscv: build-native runtime
	@echo ""
	@echo "========================================="
	@echo "Running RISC-V qemu tests with answer comparison..."
	@echo "========================================="
	@./test_enum_qemu.sh

# 运行官方测试用例（失败时正确报告）
test-official: build-native runtime
	@echo ""
	@echo "========================================="
	@echo "Running official test cases with answer comparison..."
	@echo "========================================="
	@./test_official_cases.sh

# 测试单个文件（native）
# 用法: make test-file FILE=test_enum3.mbt
test-file: build-native-debug
	@if [ -z "$(FILE)" ]; then \
		echo "Error: Please specify FILE=<filename>"; \
		echo "Example: make test-file FILE=test_enum3.mbt"; \
		exit 1; \
	fi
	@echo "Testing $(FILE)..."
	@$(COMPILER_NATIVE_DEBUG) $(FILE) -o /tmp/test.ll && echo "✓ Compilation successful (debug)"

# 测试单个文件（RISC-V qemu）
# 用法: make test-file-riscv FILE=test_enum3.mbt
test-file-riscv: build-native runtime
	@if [ -z "$(FILE)" ]; then \
		echo "Error: Please specify FILE=<filename>"; \
		echo "Example: make test-file-riscv FILE=test_enum3.mbt"; \
		exit 1; \
	fi
	@echo "Testing $(FILE) on RISC-V..."
	@TEST_NAME=$$(basename $(FILE) .mbt); \
	$(COMPILER_NATIVE_RELEASE) $(FILE) -o /tmp/$$TEST_NAME.ll && \
	clang --target=riscv64-linux-gnu --sysroot=/usr/riscv64-linux-gnu \
		-c /tmp/$$TEST_NAME.ll -o /tmp/$$TEST_NAME.o \
		-O0 -march=rv64gc -mabi=lp64d 2>/dev/null && \
	riscv64-linux-gnu-gcc -static -o /tmp/$$TEST_NAME.out \
		/tmp/$$TEST_NAME.o $(RUNTIME_LIB) \
		-O0 -march=rv64gc -mabi=lp64d -lc -lm 2>/dev/null && \
	echo "Running on qemu-riscv64..." && \
	timeout 5 qemu-riscv64 /tmp/$$TEST_NAME.out && \
	echo "✓ Test passed"

# 清理生成的文件
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf target/
	@rm -f test_output/*.ll test_output/*.out test_output/*.exe
	@rm -f /tmp/*.ll /tmp/*.o /tmp/*.out
	@rm -f contest-2025-data/riscv_rt/*.o contest-2025-data/riscv_rt/libruntime.a
	@rm -f submit.zip
	@echo "✓ Clean complete"

# 打包提交（使用 wasm-gc 版本）
submit: build-wasm
	@echo "Creating submission package..."
	@git archive -o submit.zip HEAD
	@echo "✓ Created submit.zip"
	@echo ""
	@echo "Submission checklist:"
	@echo "  [✓] wasm-gc build successful"
	@echo "  [✓] submit.zip created"
	@echo "  [ ] Run 'make test' to verify all tests pass"
	@echo "  [ ] Upload submit.zip to the submission platform"

# 帮助信息
help:
	@echo "MiniMoonBit Compiler Makefile"
	@echo ""
	@echo "Build Targets:"
	@echo "  make build-wasm      - Build wasm-gc version (for submission)"
	@echo "  make build-native    - Build native version (for development)"
	@echo "  make build           - Build both wasm-gc and native"
	@echo "  make runtime         - Build RISC-V runtime library"
	@echo ""
	@echo "Test Targets:"
	@echo "  make test            - Run all tests (native + riscv + official)"
	@echo "  make test-native     - Run native compilation tests"
	@echo "  make test-riscv      - Run RISC-V qemu tests"
	@echo "  make test-official   - Run official test cases"
	@echo "  make test-file FILE=<file>       - Test single file (native)"
	@echo "  make test-file-riscv FILE=<file> - Test single file (riscv)"
	@echo ""
	@echo "Other Targets:"
	@echo "  make clean           - Clean build artifacts"
	@echo "  make submit          - Create submission package"
	@echo "  make help            - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make build-native"
	@echo "  make test-native"
	@echo "  make test-file FILE=test_enum3.mbt"
	@echo "  make test-file-riscv FILE=test_enum3.mbt"
	@echo "  make submit"
