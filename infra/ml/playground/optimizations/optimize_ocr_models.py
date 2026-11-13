import argparse
import copy
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

import numpy as np
import onnx
from onnx import helper, numpy_helper

DOMAIN = "ente.ocr.weights"
SOURCE_BASE_URL = "https://models.ente.com/PP-OCRv5"
SOURCE_HASHES = {
    "cls.onnx": "f4bb53707100c5f3d59ba834eb05bb400369f20aed35d4b26807b1bfadd2a70e",
    "det.onnx": "d7fe3ea74652890722c0f4d02458b7261d9f5ae6c92904d05707c9eb155c7924",
    "ppocrv5_dict.txt": "d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b",
    "rec.onnx": "bf66820f48fa99f779974c4df78e5274a9d8e0458c4137e8c5357e40e2c3faf2",
}
OUTPUT_HASHES = {
    "det_fixed_v1.onnx": "f655f119225b579fa8c3cbf64f6bb7cf56a26c9dc211706a25234d70a543ec8c",
    "cls_fixed_v1.onnx": "378d52a73263828d08d4dda37f1d0aac2e36cbd486fdc6351bf309d515610654",
    "rec_fixed_v1.onnx": "6dda4c0891af5a70c5b0f618b62588df7f3140616d1c560be5ec6496747b54fd",
}


def constant_arrays(model):
    result = {v.name: numpy_helper.to_array(v) for v in model.graph.initializer}
    for node in model.graph.node:
        if node.op_type == "Constant":
            for attr in node.attribute:
                if attr.name == "value":
                    result[node.output[0]] = numpy_helper.to_array(attr.t)
    return result


def remove_unused_nodes(model):
    producers = {v: node for node in model.graph.node for v in node.output}
    needed = set()
    pending = [v.name for v in model.graph.output]
    while pending:
        name = pending.pop()
        if name in needed:
            continue
        needed.add(name)
        if name in producers:
            pending.extend(producers[name].input)
    nodes = [n for n in model.graph.node if any(v in needed for v in n.output)]
    del model.graph.node[:]
    model.graph.node.extend(nodes)
    for field in ["initializer", "value_info"]:
        values = [v for v in getattr(model.graph, field) if v.name in needed]
        del getattr(model.graph, field)[:]
        getattr(model.graph, field).extend(values)
    return model


def canonicalize_scalar_affines(model):
    values = constant_arrays(model)
    inferred = onnx.shape_inference.infer_shapes(model)
    shapes = {v.name: v.type.tensor_type.shape for v in inferred.graph.value_info}
    count = 0
    for node in model.graph.node:
        if node.op_type not in ["Mul", "Add"]:
            continue
        indices = [
            i for i, n in enumerate(node.input) if n in values and values[n].size == 1
        ]
        if len(indices) != 1:
            continue
        index = indices[0]
        value = values[node.input[index]].reshape(())
        if value.dtype != np.float32:
            continue
        replacement = value if node.op_type == "Mul" else None
        shape = shapes.get(node.output[0])
        if (
            node.op_type == "Add"
            and shape is not None
            and (len(shape.dim) == 4)
            and shape.dim[1].dim_value
        ):
            replacement = np.full(
                (shape.dim[1].dim_value, 1, 1), value, dtype=np.float32
            )
        if replacement is None:
            continue
        name = f"modelopt_affine_{count}"
        model.graph.initializer.append(numpy_helper.from_array(replacement, name))
        node.input[:] = [node.input[1 - index], name]
        count += 1
    return (remove_unused_nodes(model), count)


def scalar_affine_input(node, values):
    if node.op_type not in ["Mul", "Add"]:
        return None
    indices = [
        i
        for i, n in enumerate(node.input)
        if n in values and values[n].size and np.all(values[n] == values[n].flat[0])
    ]
    if len(indices) != 1:
        return None
    index = indices[0]
    return (node.input[1 - index], float(values[node.input[index]].flat[0]))


def fold_input_affine(model):
    values = constant_arrays(model)
    producers = {v: n for n in model.graph.node for v in n.output}
    count = 0
    for node in model.graph.node:
        if node.op_type != "Conv" or node.input[1] not in values:
            continue
        attrs = {a.name: helper.get_attribute_value(a) for a in node.attribute}
        if any(attrs.get("pads", [])) or attrs.get("auto_pad", b"NOTSET") != b"NOTSET":
            continue
        current = node.input[0]
        scale, bias, steps = (1.0, 0.0, 0)
        while current in producers:
            parent = producers[current]
            affine = scalar_affine_input(parent, values)
            if affine is None:
                break
            current, value = affine
            if parent.op_type == "Mul":
                scale *= value
            else:
                bias += scale * value
            steps += 1
        if not steps:
            continue
        weights = values[node.input[1]]
        old_bias = (
            values[node.input[2]]
            if len(node.input) > 2
            else np.zeros(weights.shape[0], dtype=np.float32)
        )
        new_weights = (weights.astype(np.float64) * scale).astype(np.float32)
        new_bias = (
            old_bias.astype(np.float64)
            + weights.astype(np.float64).sum(axis=tuple(range(1, weights.ndim))) * bias
        ).astype(np.float32)
        weight_name, bias_name = (
            f"modelopt_input_weight_{count}",
            f"modelopt_input_bias_{count}",
        )
        model.graph.initializer.extend(
            [
                numpy_helper.from_array(new_weights, weight_name),
                numpy_helper.from_array(new_bias, bias_name),
            ]
        )
        node.input[:] = [current, weight_name, bias_name]
        count += 1
    return (remove_unused_nodes(model), count)


def fuse_recognizer_layer_norms(model):
    model = onnx.version_converter.convert_version(model, 17)
    values = constant_arrays(model)
    specs = [
        ("Add.187", "Add.191", "layer_norm_1", "helper.constant.26"),
        ("Add.197", "Add.201", "layer_norm_2", "helper.constant.33"),
        ("Add.207", "Add.211", "layer_norm_3", "helper.constant.49"),
        ("Add.217", "Add.221", "layer_norm_4", "helper.constant.56"),
    ]
    count = 0
    for source, output, prefix, epsilon in specs:
        index = next((i for i, n in enumerate(model.graph.node) if output in n.output))
        weight_name, bias_name = (
            f"{prefix}_modelopt_weight",
            f"{prefix}_modelopt_bias",
        )
        model.graph.initializer.extend(
            [
                numpy_helper.from_array(
                    values[prefix + ".w_0"].reshape(-1), weight_name
                ),
                numpy_helper.from_array(values[prefix + ".b_0"].reshape(-1), bias_name),
            ]
        )
        model.graph.node[index].CopyFrom(
            helper.make_node(
                "LayerNormalization",
                [source, weight_name, bias_name],
                [output],
                name=prefix + "_modelopt",
                axis=-1,
                epsilon=float(values[epsilon].item()),
                stash_type=1,
            )
        )
        count += 1
    return (remove_unused_nodes(model), count)


def expand_hardswish(model):
    nodes = []
    for node in model.graph.node:
        if node.op_type != "HardSwish":
            nodes.append(node)
            continue
        name = node.output[0] + "_modelopt_gate"
        nodes.extend(
            [
                helper.make_node(
                    "HardSigmoid",
                    [node.input[0]],
                    [name],
                    name=node.name + "_gate",
                    alpha=1 / 6,
                    beta=0.5,
                ),
                helper.make_node(
                    "Mul",
                    [node.input[0], name],
                    list(node.output),
                    name=node.name + "_multiply",
                ),
            ]
        )
    del model.graph.node[:]
    model.graph.node.extend(nodes)
    return model


def compact_recognizer_output(model):
    output = model.graph.output[0].name
    model.graph.initializer.extend(
        [
            numpy_helper.from_array(
                np.arange(18385, dtype=np.float32).reshape(1, 1, -1), "shared_positions"
            ),
            numpy_helper.from_array(
                np.array(18385, dtype=np.float32), "shared_sentinel"
            ),
        ]
    )
    model.graph.node.extend(
        [
            helper.make_node(
                "ReduceMax",
                [output],
                ["shared_score"],
                axes=[2],
                keepdims=1,
                name="shared_score",
            ),
            helper.make_node(
                "Sub", ["shared_score", output], ["shared_gap"], name="shared_gap"
            ),
            helper.make_node(
                "Ceil", ["shared_gap"], ["shared_nonwinner"], name="shared_nonwinner"
            ),
            helper.make_node(
                "Mul",
                ["shared_nonwinner", "shared_sentinel"],
                ["shared_penalty"],
                name="shared_penalty",
            ),
            helper.make_node(
                "Add",
                ["shared_positions", "shared_penalty"],
                ["shared_candidates"],
                name="shared_candidates",
            ),
            helper.make_node(
                "ReduceMin",
                ["shared_candidates"],
                ["shared_index"],
                axes=[2],
                keepdims=1,
                name="shared_index",
            ),
            helper.make_node(
                "Concat",
                ["shared_index", "shared_score"],
                ["shared_output"],
                axis=2,
                name="shared_output",
            ),
        ]
    )
    del model.graph.output[:]
    model.graph.output.append(
        helper.make_tensor_value_info(
            "shared_output", onnx.TensorProto.FLOAT, ["N", "T", 2]
        )
    )
    return remove_unused_nodes(model)


def fold_detector_head(model):
    values = constant_arrays(model)
    nodes = list(model.graph.node)
    for node in nodes:
        if (
            node.op_type == "Reshape"
            and node.input[0] in values
            and (node.input[1] in values)
        ):
            values[node.output[0]] = values[node.input[0]].reshape(
                values[node.input[1]]
            )
    replacements = {}
    for ordinal, node in enumerate([n for n in nodes if n.op_type == "ConvTranspose"]):
        attrs = {a.name: helper.get_attribute_value(a) for a in node.attribute}
        assert attrs["group"] == 1 and attrs["kernel_shape"] == [2, 2]
        assert attrs["strides"] == [2, 2] and (not any(attrs["pads"]))
        add = next(n for n in nodes if node.output[0] in n.input and n.op_type == "Add")
        bias_input = next(v for v in add.input if v != node.output[0])
        weight = values[node.input[1]].astype(np.float64)
        bias = values[bias_input].reshape(-1).astype(np.float64)
        output = add.output[0]
        bn = next(
            (
                n
                for n in nodes
                if output in n.input and n.op_type == "BatchNormalization"
            ),
            None,
        )
        if bn is not None:
            attrs_bn = {a.name: helper.get_attribute_value(a) for a in bn.attribute}
            assert not attrs_bn.get("training_mode", 0)
            scale, offset, mean, variance = [
                values[v].astype(np.float64) for v in bn.input[1:]
            ]
            factor = scale / np.sqrt(variance + attrs_bn["epsilon"])
            weight *= factor[None, :, None, None]
            bias = (bias - mean) * factor + offset
            output = bn.output[0]
        weight_name, bias_name = (
            f"modelopt_deconv_weight_{ordinal}",
            f"modelopt_deconv_bias_{ordinal}",
        )
        fused = copy.deepcopy(node)
        fused.input[:] = [node.input[0], weight_name, bias_name]
        fused.output[:] = [output]
        replacements[node.name] = [fused]
        model.graph.initializer.extend(
            [
                numpy_helper.from_array(weight.astype(np.float32), weight_name),
                numpy_helper.from_array(bias.astype(np.float32), bias_name),
            ]
        )
        replacements[add.name] = []
        if bn is not None:
            replacements[bn.name] = []
    del model.graph.node[:]
    for node in nodes:
        model.graph.node.extend(replacements.get(node.name, [node]))
    return remove_unused_nodes(model)


def rewrite_classifier_hardswish(model):
    values = constant_arrays(model)
    producers = {v: n for n in model.graph.node for v in n.output}
    nodes = []
    count = 0
    for node in model.graph.node:
        matched = False
        if (
            node.op_type == "Div"
            and node.input[1] in values
            and np.all(values[node.input[1]] == 6)
        ):
            multiply = producers.get(node.input[0])
            if multiply is not None and multiply.op_type == "Mul":
                for index in [0, 1]:
                    clip = producers.get(multiply.input[index])
                    source = multiply.input[1 - index]
                    if clip is None or clip.op_type != "Clip" or len(clip.input) != 3:
                        continue
                    if (
                        clip.input[1] not in values
                        or clip.input[2] not in values
                        or (not np.all(values[clip.input[1]] == 0))
                        or (not np.all(values[clip.input[2]] == 6))
                    ):
                        continue
                    add = producers.get(clip.input[0])
                    if add is None or add.op_type != "Add" or source not in add.input:
                        continue
                    other = add.input[1 - list(add.input).index(source)]
                    if other not in values or not np.all(values[other] == 3):
                        continue
                    gate = f"modelopt_cls_gate_{count}"
                    nodes.extend(
                        [
                            helper.make_node(
                                "HardSigmoid",
                                [source],
                                [gate],
                                name=gate,
                                alpha=1 / 6,
                                beta=0.5,
                            ),
                            helper.make_node(
                                "Mul",
                                [source, gate],
                                list(node.output),
                                name=node.name + "_modelopt",
                            ),
                        ]
                    )
                    count += 1
                    matched = True
                    break
        if not matched:
            nodes.append(node)
    del model.graph.node[:]
    model.graph.node.extend(nodes)
    return (remove_unused_nodes(model), count)


def shaped(source_model, shape):
    model = copy.deepcopy(source_model)
    for dim, value in zip(model.graph.input[0].type.tensor_type.shape.dim, shape):
        dim.dim_value = value
    del model.graph.value_info[:]
    for output in model.graph.output:
        output.type.tensor_type.ClearField("shape")
    return onnx.shape_inference.infer_shapes(model, data_prop=True)


def dimensions(model):
    return {
        value.name: [dim.dim_value for dim in value.type.tensor_type.shape.dim]
        for value in [*model.graph.input, *model.graph.value_info, *model.graph.output]
    }


def detector_model(source_model, shape):
    model = shaped(source_model, shape)
    sizes = dimensions(model)
    nodes = []
    masks = {}
    mask_cache = {}

    def auxiliary(name, dims, tensor, kind):
        if name not in masks:
            model.graph.input.append(
                helper.make_tensor_value_info(name, onnx.TensorProto.FLOAT, dims)
            )
            masks[name] = {"shape": dims, "tensor": tensor, "kind": kind}
        return name

    def mask(tensor):
        if tensor in mask_cache:
            return mask_cache[tensor]
        n, _, h, w = sizes[tensor]
        dims = [n, 1, h, w]
        name = auxiliary(f"mask_{h}_{w}", dims, tensor, "spatial")
        out = tensor + "_masked"
        nodes.append(helper.make_node("Mul", [tensor, name], [out], name=out))
        mask_cache[tensor] = out
        return out

    for original in model.graph.node:
        node = copy.deepcopy(original)
        if node.op_type in [
            "Conv",
            "AveragePool",
            "GlobalAveragePool",
        ]:
            dims = sizes.get(node.input[0], [])
            attrs = {a.name: helper.get_attribute_value(a) for a in node.attribute}
            spatial = len(dims) == 4 and dims[-1] > 1
            mixing = node.op_type != "Conv" or any(
                k > 1 for k in attrs.get("kernel_shape", [1, 1])
            )
            if spatial and mixing:
                node.input[0] = mask(original.input[0])
        if node.op_type == "GlobalAveragePool":
            n, _, h, w = sizes[original.input[0]]
            scale = auxiliary(
                f"pool_scale_{h}_{w}", [n, 1, 1, 1], original.input[0], "scale"
            )
            output = node.output[0]
            node.output[0] = output + "_uncorrected"
            nodes.append(node)
            nodes.append(
                helper.make_node(
                    "Mul", [node.output[0], scale], [output], name=output + "_correct"
                )
            )
            continue
        if node.op_type == "Softmax" and len(sizes[node.input[0]]) == 4:
            n, _, _, w = sizes[node.input[0]]
            name = auxiliary(
                "attention_bias", [n, 1, 1, w], original.input[0], "attention"
            )
            out = node.input[0] + "_masked"
            nodes.append(
                helper.make_node("Add", [node.input[0], name], [out], name=out)
            )
            node.input[0] = out
        nodes.append(node)
    del model.graph.node[:]
    model.graph.node.extend(nodes)
    del model.graph.value_info[:]
    model = onnx.shape_inference.infer_shapes(model, data_prop=True)
    onnx.checker.check_model(model)
    return model, masks


def recognizer_model(source_model, width, slots):
    model = shaped(source_model, [1, 3, 48, width])
    sizes = dimensions(model)
    nodes = []
    metadata = {}
    seen = {}
    gates = {}

    def aux(name, shape, tensor, kind):
        if name not in metadata:
            model.graph.input.append(
                helper.make_tensor_value_info(name, onnx.TensorProto.FLOAT, shape)
            )
            metadata[name] = {"shape": shape, "tensor": tensor, "kind": kind}
        return name

    def const(name, value):
        model.graph.initializer.append(
            numpy_helper.from_array(np.asarray(value, np.int64), name)
        )
        return name

    def mask(tensor):
        if tensor in seen:
            return seen[tensor]
        _, _, h, w = sizes[tensor]
        name = aux(f"mask_{h}_{w}", [1, 1, 1, w], tensor, "spatial")
        out = tensor + "_masked"
        nodes.append(helper.make_node("Mul", [tensor, name], [out], name=out))
        seen[tensor] = out
        return out

    for original in model.graph.node:
        node = copy.deepcopy(original)
        if node.op_type == "GlobalAveragePool":
            tensor = node.input[0]
            _, c, _, w = sizes[tensor]
            prefix = node.output[0] + "_packed"
            weights = aux(f"pool_weights_{w}", [1, w, slots], tensor, "pool")
            nodes.extend(
                [
                    helper.make_node(
                        "ReduceMean",
                        [tensor],
                        [prefix + "_height"],
                        axes=[2],
                        keepdims=0,
                    ),
                    helper.make_node(
                        "MatMul", [prefix + "_height", weights], [prefix + "_means"]
                    ),
                    helper.make_node(
                        "Transpose",
                        [prefix + "_means"],
                        [prefix + "_transposed"],
                        perm=[2, 1, 0],
                    ),
                    helper.make_node(
                        "Reshape",
                        [
                            prefix + "_transposed",
                            const(prefix + "_shape", [slots, c, 1, 1]),
                        ],
                        [node.output[0]],
                    ),
                ]
            )
            gate = "p2o.pd_op.hardsigmoid." + (
                "0.0" if "pool2d.0" in node.output[0] else "1.0"
            )
            gates[gate] = (c, w, tensor)
            continue
        if node.op_type in ["Conv", "AveragePool"]:
            dims = sizes.get(node.input[0], [])
            attrs = {a.name: helper.get_attribute_value(a) for a in node.attribute}
            if (
                len(dims) == 4
                and dims[-1] > 1
                and (
                    node.op_type != "Conv"
                    or any(k > 1 for k in attrs.get("kernel_shape", [1, 1]))
                )
            ):
                node.input[0] = mask(node.input[0])
        if node.op_type == "Softmax" and len(sizes[node.input[0]]) == 4:
            t = sizes[node.input[0]][-1]
            name = aux("attention_bias", [1, 1, t, t], node.input[0], "attention")
            out = node.input[0] + "_masked"
            nodes.append(
                helper.make_node("Add", [node.input[0], name], [out], name=out)
            )
            node.input[0] = out
        output = node.output[0]
        if output in gates:
            c, w, tensor = gates[output]
            node.output[0] = output + "_slots"
            weights = aux(f"gate_weights_{w}", [1, slots, w], tensor, "gate")
            nodes.extend(
                [
                    node,
                    helper.make_node(
                        "Reshape",
                        [node.output[0], const(output + "_flatshape", [slots, c])],
                        [output + "_flat"],
                    ),
                    helper.make_node(
                        "Transpose",
                        [output + "_flat"],
                        [output + "_transposed"],
                        perm=[1, 0],
                    ),
                    helper.make_node(
                        "MatMul",
                        [output + "_transposed", weights],
                        [output + "_mapped"],
                    ),
                    helper.make_node(
                        "Reshape",
                        [output + "_mapped", const(output + "_shape", [1, c, 1, w])],
                        [output],
                    ),
                ]
            )
        else:
            nodes.append(node)
    del model.graph.node[:]
    model.graph.node.extend(nodes)
    del model.graph.value_info[:]
    for output in model.graph.output:
        output.type.tensor_type.ClearField("shape")
    model = onnx.shape_inference.infer_shapes(model, data_prop=True)
    onnx.checker.check_model(model)
    return model, metadata


def pad_vocabulary(model):
    values = constant_arrays(model)
    projection = next(n for n in model.graph.node if n.name == "MatMul.12")
    weights = values[projection.input[1]]
    assert weights.shape == (120, 18385)
    add = next(
        node
        for node in model.graph.node
        if node.op_type == "Add" and projection.output[0] in node.input
    )
    bias = values[next(name for name in add.input if name in values)].reshape(-1)
    assert bias.size == 18385
    insertion = next(
        i
        for i, value in enumerate(model.graph.initializer)
        if value.name == "shared_positions"
    )
    model.graph.initializer.insert(
        insertion,
        numpy_helper.from_array(
            np.pad(weights, ((0, 0), (0, 47))), "modelopt_projection_weight"
        ),
    )
    projection.input[1] = "modelopt_projection_weight"
    original = projection.output[0]
    projection.output[0] = "modelopt_padded_projection"
    add.input[:] = [
        projection.output[0] if name == original else name for name in add.input
    ]
    model = remove_unused_nodes(model)
    insertion = next(
        i
        for i, value in enumerate(model.graph.initializer)
        if value.name == "shared_positions"
    )
    published_slice_constants = [("start", 0), ("end", 18385), ("axis", 2)]
    for offset, (name, value) in enumerate(published_slice_constants):
        model.graph.initializer.insert(
            insertion + offset,
            numpy_helper.from_array(
                np.array([value], dtype=np.int64), f"modelopt_slice_{name}"
            ),
        )
    model.graph.initializer.append(
        numpy_helper.from_array(
            np.pad(bias, (0, 47), constant_values=-np.inf), "vocabulary_bias_padded"
        )
    )
    add = next(
        node
        for node in model.graph.node
        if node.op_type == "Add" and "modelopt_padded_projection" in node.input
    )
    add.input[:] = ["modelopt_padded_projection", "vocabulary_bias_padded"]
    for value in model.graph.initializer:
        if value.name == "shared_positions":
            value.CopyFrom(
                numpy_helper.from_array(
                    np.arange(18432, dtype=np.float32).reshape(1, 1, -1),
                    "shared_positions",
                )
            )
    del model.graph.value_info[:]
    model = onnx.shape_inference.infer_shapes(model, data_prop=True)
    onnx.checker.check_model(model)
    return model


def align_attention(model):
    model = copy.deepcopy(model)
    sizes = dimensions(model)
    nodes = []

    def constant(name, values):
        model.graph.initializer.append(
            numpy_helper.from_array(np.asarray(values, np.int64), name)
        )
        return name

    def pad(name, tensor, axis):
        pads = [0] * 8
        pads[4 + axis] = 1
        nodes.append(
            helper.make_node(
                "Pad", [tensor, constant(name + "_pads", pads)], [name], name=name
            )
        )
        return name

    for original in model.graph.node:
        node = copy.deepcopy(original)
        if node.op_type == "MatMul":
            a = sizes.get(node.input[0], [])
            b = sizes.get(node.input[1], [])
            if len(a) == 4 and a[-1] == 15 and len(b) == 4 and b[-2] == 15:
                node.input[0] = pad(node.output[0] + "_q16", node.input[0], 3)
                node.input[1] = pad(node.output[0] + "_k16", node.input[1], 2)
            elif len(a) == 4 and len(b) == 4 and a[-1] == b[-2] and b[-1] == 15:
                node.input[1] = pad(node.output[0] + "_v16", node.input[1], 3)
                output = node.output[0]
                node.output[0] = output + "_16"
                nodes.append(node)
                nodes.append(
                    helper.make_node(
                        "Slice",
                        [
                            node.output[0],
                            constant(output + "_start", [0]),
                            constant(output + "_end", [15]),
                            constant(output + "_axis", [3]),
                        ],
                        [output],
                        name=output + "_trim",
                    )
                )
                continue
        nodes.append(node)
    del model.graph.node[:]
    model.graph.node.extend(nodes)
    del model.graph.value_info[:]
    model = onnx.shape_inference.infer_shapes(model, data_prop=True)
    onnx.checker.check_model(model, full_check=True)
    return model


def with_fixed_paths(source_model, stage, shapes):
    maximum = [1, 3, 960, 960] if stage == "det" else [1, 3, 48, 7168]
    output_shape = [1, 1, 960, 960] if stage == "det" else [1, 896, 2]
    outer_inputs = [helper.make_tensor_value_info("x", onnx.TensorProto.FLOAT, maximum)]
    weights = {}
    branches = []
    metadata = []
    for index, shape in enumerate(shapes):
        label = f"p{index}"
        if stage == "det":
            model, meta = detector_model(source_model, shape)
        else:
            model, meta = recognizer_model(source_model, shape[-1], shape[-1] // 336)
            model = align_attention(pad_vocabulary(model))
        mapping = {}
        local_weights = set()
        tensors = [
            (n.output[0], a.t)
            for n in model.graph.node
            if n.op_type == "Constant"
            for a in n.attribute
            if a.name == "value" and a.t.data_type == onnx.TensorProto.FLOAT
        ]
        tensors.extend(
            (t.name, t)
            for t in model.graph.initializer
            if t.data_type == onnx.TensorProto.FLOAT
        )
        for original_name, original in tensors:
            tensor = copy.deepcopy(original)
            tensor.name = ""
            name = "w" + hashlib.sha256(tensor.SerializeToString()).hexdigest()
            tensor.name = name
            weights[name] = tensor
            mapping[original_name] = name
            local_weights.add(name)

        def rename(name, mapping=mapping, label=label):
            return mapping.get(name, label + "_" + name) if name else name

        nodes = [
            helper.make_node(name, [], [name], domain=DOMAIN, name=label + "_" + name)
            for name in sorted(local_weights)
        ]
        initializers = []
        for name, values in [
            ("starts", [0, 0]),
            ("ends", shape[-2:]),
            ("axes", [2, 3]),
        ]:
            initializers.append(
                numpy_helper.from_array(
                    np.asarray(values, np.int64), label + "_" + name
                )
            )
        nodes.append(
            helper.make_node(
                "Slice",
                ["x", label + "_starts", label + "_ends", label + "_axes"],
                [rename("x")],
                name=label + "_slice",
            )
        )
        for value in list(model.graph.input)[1:]:
            item = copy.deepcopy(value)
            item.name = rename(value.name)
            outer_inputs.append(item)
        for tensor in model.graph.initializer:
            if tensor.name not in mapping:
                item = copy.deepcopy(tensor)
                item.name = rename(item.name)
                initializers.append(item)
        for ni, node in enumerate(model.graph.node):
            if node.output[0] in mapping:
                continue
            item = copy.deepcopy(node)
            item.name = label + "_" + str(ni) + "_" + node.name
            for i, name in enumerate(item.input):
                item.input[i] = rename(name)
            for i, name in enumerate(item.output):
                item.output[i] = rename(name)
            nodes.append(item)
        output = rename(model.graph.output[0].name)
        original_output = (
            [1, 1, *shape[-2:]] if stage == "det" else [1, shape[-1] // 8, 2]
        )
        if original_output != output_shape:
            padding = [0] * len(output_shape) + [
                a - b for a, b in zip(output_shape, original_output)
            ]
            initializers.append(
                numpy_helper.from_array(np.asarray(padding, np.int64), label + "_pads")
            )
            nodes.append(
                helper.make_node(
                    "Pad",
                    [output, label + "_pads"],
                    [label + "_output"],
                    name=label + "_pad",
                )
            )
            output = label + "_output"
        graph = helper.make_graph(
            nodes,
            label,
            [],
            [
                helper.make_tensor_value_info(
                    output, onnx.TensorProto.FLOAT, output_shape
                )
            ],
            initializer=initializers,
        )
        for value in [*model.graph.input, *model.graph.value_info]:
            item = copy.deepcopy(value)
            item.name = rename(item.name)
            graph.value_info.append(item)
        branches.append(graph)
        metadata.append({"shape": shape, "auxiliary": meta})
    branch = branches[-1]
    for i in range(len(branches) - 2, -1, -1):
        name = f"path_{i}"
        outer_inputs.append(
            helper.make_tensor_value_info(name, onnx.TensorProto.BOOL, [])
        )
        node = helper.make_node(
            "If",
            [name],
            [f"selected_{i}"],
            name=f"select_{i}",
            then_branch=branches[i],
            else_branch=branch,
        )
        branch = helper.make_graph(
            [node],
            f"selection_{i}",
            [],
            [
                helper.make_tensor_value_info(
                    f"selected_{i}", onnx.TensorProto.FLOAT, output_shape
                )
            ],
        )
    graph = helper.make_graph(
        branch.node, f"{stage}_static_paths", outer_inputs, branch.output
    )
    model = helper.make_model(
        graph,
        opset_imports=[helper.make_opsetid("", 17), helper.make_opsetid(DOMAIN, 1)],
        ir_version=10,
    )
    for name, tensor in weights.items():
        model.functions.append(
            helper.make_function(
                DOMAIN,
                name,
                [],
                ["value"],
                [helper.make_node("Constant", [], ["value"], value=tensor)],
                [helper.make_opsetid("", 17)],
            )
        )
    onnx.checker.check_model(model, full_check=True)
    return model, metadata


def fixed_models(models):
    detector, _ = with_fixed_paths(
        models["det.onnx"],
        "det",
        [
            [1, 3, 960, 480],
            [1, 3, 480, 960],
            [1, 3, 960, 704],
            [1, 3, 704, 960],
            [1, 3, 960, 960],
        ],
    )
    recognizer, _ = with_fixed_paths(
        models["rec.onnx"], "rec", [[1, 3, 48, 2048], [1, 3, 48, 7168]]
    )
    classifier = copy.deepcopy(models["cls.onnx"])
    classifier.graph.input[0].type.tensor_type.shape.CopyFrom(
        helper.make_tensor_value_info(
            "x", onnx.TensorProto.FLOAT, [6, 3, 48, 192]
        ).type.tensor_type.shape
    )
    del classifier.graph.value_info[:]
    for value in classifier.graph.output:
        for dim in value.type.tensor_type.shape.dim:
            dim.ClearField("dim_param")
            dim.ClearField("dim_value")
    classifier = onnx.shape_inference.infer_shapes(classifier)
    return {
        "det_fixed_v1.onnx": detector,
        "cls_fixed_v1.onnx": classifier,
        "rec_fixed_v1.onnx": recognizer,
    }


def load_sources(directory):
    models = {}
    directory.mkdir(parents=True, exist_ok=True)
    for name, expected in SOURCE_HASHES.items():
        path = directory / name
        if not path.exists():
            request = Request(
                f"{SOURCE_BASE_URL}/{name}",
                headers={"User-Agent": "ente-ml-model-optimizer"},
            )
            with urlopen(request, timeout=120) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != expected:
                raise ValueError(f"Unexpected SHA-256 for downloaded {name}")
            path.write_bytes(data)
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Unexpected SHA-256 for {path}")
        if path.suffix == ".onnx":
            models[path.stem] = onnx.load(path)
    return models


def optimize(models):
    recognition, _ = canonicalize_scalar_affines(copy.deepcopy(models["rec"]))
    recognition, folded = fold_input_affine(recognition)
    recognition, normalized = fuse_recognizer_layer_norms(recognition)
    if folded != 12 or normalized != 4:
        raise ValueError(
            f"Unexpected recognizer rewrites: folded={folded!r}, normalized={normalized!r}"
        )
    recognition = expand_hardswish(recognition)
    recognition = compact_recognizer_output(recognition)
    detection = fold_detector_head(copy.deepcopy(models["det"]))
    detection = expand_hardswish(detection)
    classification, _ = canonicalize_scalar_affines(copy.deepcopy(models["cls"]))
    classification, activations = rewrite_classifier_hardswish(classification)
    if activations != 18:
        raise ValueError(f"Unexpected classifier rewrites: activations={activations!r}")
    return {
        "det.onnx": detection,
        "cls.onnx": classification,
        "rec.onnx": recognition,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if onnx.__version__ != "1.22.0":
        raise ValueError("Reproducible model output requires onnx==1.22.0")
    if np.__version__ != "2.5.3":
        raise ValueError("Reproducible model output requires numpy==2.5.3")
    sources = load_sources(args.source_dir)
    records = []
    for name, model in fixed_models(optimize(sources)).items():
        onnx.checker.check_model(model, full_check=True)
        for value in model.graph.input:
            if any(
                not d.HasField("dim_value") or d.dim_value <= 0
                for d in value.type.tensor_type.shape.dim
            ):
                raise ValueError(f"Non-static input {value.name} in {name}")
        data = model.SerializeToString()
        digest = hashlib.sha256(data).hexdigest()
        if digest != OUTPUT_HASHES[name]:
            raise ValueError(
                f"Generated model differs from qualified artifact: {name} ({digest})"
            )
        path = args.output_dir / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        records.append(
            {
                "file": name,
                "sha256": digest,
                "bytes": len(data),
                "inputs": {
                    value.name: [d.dim_value for d in value.type.tensor_type.shape.dim]
                    for value in model.graph.input
                },
                "output": "FP32 [1,896,2]: packed first winning index and probability"
                if name == "rec_fixed_v1.onnx"
                else "unchanged",
            }
        )
    if sum(record["bytes"] for record in records) > 25_000_000:
        raise ValueError("The combined OCR models exceed 25 MB")
    dictionary = args.source_dir / "ppocrv5_dict.txt"
    (args.output_dir / dictionary.name).write_bytes(dictionary.read_bytes())
    metadata = {
        "format": "ente-ocr-fixed-v1",
        "requires_context_adapter": True,
        "detector_paths": [[960, 480], [480, 960], [960, 704], [704, 960], [960, 960]],
        "recognizer_widths": [2048, 7168],
        "source_base_url": SOURCE_BASE_URL,
        "source_sha256": SOURCE_HASHES,
        "onnx": onnx.__version__,
        "models": records,
    }
    (args.output_dir / "ocr_model_manifest.json").write_text(
        json.dumps(metadata, indent=2) + "\n"
    )
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
