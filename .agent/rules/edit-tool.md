# Edit 工具使用铁律

## 核心规则

1. **替换 = pos + end**（永远成对出现，不能只有 pos）
2. **每次 edit 后必须验证**（read 检查结果）
3. **复杂改动分多次进行**

## 正确示例

### 替换单行
```python
{"pos": "2#KV", "end": "2#KV", "lines": "    total = 1", "op": "replace"}
```

### 替换多行
```python
{"pos": "1#XX", "end": "2#YY", "lines": "L1\nL2\nL3", "op": "replace"}
```

### 替换连续块
```python
{"pos": "4#XX", "end": "7#YY", "lines": "新内容", "op": "replace"}
```

### 多个不相关改动（从下往上执行）
```python
[
  {"pos": "11#XX", "end": "12#YY", "lines": "return False", "op": "replace"},
  {"pos": "2#AA", "end": "2#AA", "lines": "    count = 0\n    total = 0", "op": "replace"}
]
```

### 追加到文件末尾
```python
{"lines": "\ndef helper():", "op": "append"}
```

## 错误示例（永远避免）

### 只有 pos 没有 end → 该行之后内容全被删除
```python
{"pos": "2#KV", "lines": "    total = 1", "op": "replace"}
```

### end 范围不匹配
```python
{"pos": "4#XX", "end": "5#YY", "lines": "..."}
```

### 同一 edits 中重叠范围 → Overlapping range 报错
```python
[
  {"pos": "4#XX", "end": "6#YY", ...},
  {"pos": "5#AA", "end": "7#BB", ...}  # 重叠！
]
```

## 记忆口诀

```
替换 = pos + end（成对出现）
验证 = 每次 edit 后 read
```
