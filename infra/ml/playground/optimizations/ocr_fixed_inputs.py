import copy
import hashlib

import numpy as np
import onnx
from onnx import helper, numpy_helper

DOMAIN = "ente.ocr.weights"


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


def pad_vocabulary(original):
    model = copy.deepcopy(original)
    values = {v.name: numpy_helper.to_array(v) for v in model.graph.initializer}
    for node in model.graph.node:
        if node.op_type == "Constant":
            for attribute in node.attribute:
                if attribute.name == "value":
                    values[node.output[0]] = numpy_helper.to_array(attribute.t)
    removed = next(
        node
        for node in model.graph.node
        if node.op_type == "Slice" and node.input[0] == "modelopt_padded_projection"
    )
    add = next(
        node
        for node in model.graph.node
        if node.op_type == "Add" and removed.output[0] in node.input
    )
    bias_name = next(name for name in add.input if name in values)
    bias = values[bias_name].reshape(-1)
    assert bias.size == 18385
    extended = np.pad(bias, (0, 18432 - bias.size), constant_values=-np.inf)
    model.graph.initializer.append(
        numpy_helper.from_array(extended, "vocabulary_bias_padded")
    )
    add.input[:] = ["modelopt_padded_projection", "vocabulary_bias_padded"]
    model.graph.node.remove(removed)
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
