# LLVM IR 优化模块

本模块提供了针对 LLVM IR 的全面优化功能，包括基本优化、循环优化、向量化优化等，旨在提高生成代码的性能。

## 目录结构

- `optimizer.mbt` - 优化器核心实现，包含基础优化功能
- `loop_opt.mbt` - 循环优化模块，包括循环不变代码外提、循环展开等
- `vectorize.mbt` - 向量化优化模块，针对 RISC-V 向量扩展(RVV)的优化
- `moon.pkg.json` - 包配置文件

## 使用方法

### 基本使用

```moonbit
use codegen.optimize

// 使用默认优化配置
let module = codegen.codegen_with_default_optimization(knf_program)

// 使用自定义优化配置
let config = optimize.default_optimization_config()
let module = codegen.codegen_with_optimization(knf_program, config)
```

### 预设优化配置

系统提供了三种预设优化配置：

1. **默认优化配置** (`default_optimization_config`)
   - 启用基本优化
   - 启用循环不变代码外提
   - 关闭循环展开（避免代码大小膨胀）
   - 关闭向量化（默认关闭）

2. **高级优化配置** (`advanced_optimization_config`)
   - 启用所有优化
   - 包括循环展开和向量化
   - 更高的内联阈值
   - 可能增加编译时间和代码大小

3. **快速优化配置** (`fast_optimization_config`)
   - 仅启用基本优化
   - 关闭循环优化和向量化
   - 减少编译时间

### 自定义优化配置

```moonbit
let custom_config = {
  enable_dead_code_elimination = true,
  enable_constant_folding = true,
  enable_instruction_combining = true,
  enable_loop_optimization = true,
  enable_licm = true,  // 循环不变代码外提
  enable_loop_unrolling = false,
  loop_unroll_threshold = 16,
  enable_function_inlining = true,
  inline_threshold = 10,
  enable_vectorization = false,  // 关闭向量化
  enable_slp_vectorization = true,
  enable_loop_vectorization = true,
  target_vector_width = 128,
  enable_global_optimization = true,
  enable_riscv_optimizations = true
}

let module = codegen.codegen_with_optimization(knf_program, custom_config)
```

## 优化功能

### 基本优化

1. **死代码消除** (`enable_dead_code_elimination`)
   - 删除未使用的指令和基本块
   - 删除未到达的代码

2. **常量折叠** (`enable_constant_folding`)
   - 在编译时计算常量表达式
   - 减少运行时计算

3. **指令合并** (`enable_instruction_combining`)
   - 合并相邻的相关指令
   - 简化表达式

### 循环优化

1. **循环不变代码外提** (`enable_licm`)
   - 将循环中不随迭代变化的指令移到循环外
   - 减少重复计算

2. **循环展开** (`enable_loop_unrolling`)
   - 复制循环体多次以减少循环开销
   - 增加指令级并行性

3. **循环剥离** (`enable_peeling`)
   - 执行前几次迭代
   - 简化循环条件

4. **归纳变量优化** (`enable_induction`)
   - 优化循环计数器
   - 识别和优化其他归纳变量

### 向量化优化

1. **超字并行向量化** (`enable_slp_vectorization`)
   - 将水平操作转换为向量操作
   - 适用于相邻相同类型的操作

2. **循环向量化** (`enable_loop_vectorization`)
   - 将循环中的操作转换为向量操作
   - 利用 SIMD 指令集

3. **RISC-V 向量扩展支持**
   - 针对 RISC-V RVV 的特定优化
   - 支持可配置的向量长度和元素宽度

### 函数优化

1. **函数内联** (`enable_function_inlining`)
   - 将小函数的代码直接插入到调用点
   - 减少函数调用开销

### 全局优化

1. **全局变量优化** (`enable_global_optimization`)
   - 删除未使用的全局变量
   - 常量传播全局变量

### RISC-V 特定优化

1. **指令模式匹配** (`enable_riscv_optimizations`)
   - 针对 RISC-V 指令集的特定优化
   - 利用 RISC-V 特有指令

## 性能考虑

- **向量化** 通常能显著提高数据并行性能，但可能增加代码大小
- **循环展开** 可以减少循环开销，但会显著增加代码大小
- **函数内联** 可以减少调用开销，但可能增加代码大小和编译时间
- **循环不变代码外提** 通常总能提高性能而不会显著增加代码大小

## 示例

### 启用向量化

```moonbit
let config = optimize.default_optimization_config().{ 
  enable_vectorization = true,
  target_vector_width = 256  // 使用 256 位向量
}

let module = codegen.codegen_with_optimization(knf_program, config)
```

### 启用循环展开

```moonbit
let config = optimize.default_optimization_config().{ 
  enable_loop_unrolling = true,
  loop_unroll_threshold = 8  // 循环体大小小于 8 时才展开
}

let module = codegen.codegen_with_optimization(knf_program, config)
```

### 针对小代码大小优化

```moonbit
let config = optimize.fast_optimization_config()

let module = codegen.codegen_with_optimization(knf_program, config)
```

### 针对最高性能优化

```moonbit
let config = optimize.advanced_optimization_config().{ 
  target_vector_width = 512,  // 使用最大向量宽度
  inline_threshold = 30  // 更激进的内联
}

let module = codegen.codegen_with_optimization(knf_program, config)
```

## 注意事项

1. 向量化需要目标架构支持 SIMD 指令
2. 过度的循环展开可能导致指令缓存未命中
3. 激进的函数内联可能显著增加代码大小
4. 某些优化可能相互影响，需要平衡

## 实现细节

本优化模块主要基于 LLVM IR，通过分析 IR 结构并应用变换来实现优化。每个优化模块都包含详细的注释，解释算法和实现细节。