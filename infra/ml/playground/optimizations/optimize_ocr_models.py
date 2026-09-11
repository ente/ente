import argparse
import copy
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

import numpy as np
import onnx
from ocr_fixed_inputs import fixed_models
from onnx import helper, numpy_helper

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


def align_recognizer_projection(model, width):
    values = constant_arrays(model)
    node = next(n for n in model.graph.node if n.name == "MatMul.12")
    weights = values[node.input[1]]
    assert weights.shape == (120, 18385)
    padded = np.pad(weights, ((0, 0), (0, width - 18385)))
    model.graph.initializer.extend(
        [
            numpy_helper.from_array(padded, "modelopt_projection_weight"),
            numpy_helper.from_array(
                np.array([0], dtype=np.int64), "modelopt_slice_start"
            ),
            numpy_helper.from_array(
                np.array([18385], dtype=np.int64), "modelopt_slice_end"
            ),
            numpy_helper.from_array(
                np.array([2], dtype=np.int64), "modelopt_slice_axis"
            ),
        ]
    )
    node.input[1] = "modelopt_projection_weight"
    output = node.output[0]
    node.output[0] = "modelopt_padded_projection"
    index = next((i for i, n in enumerate(model.graph.node) if n.name == node.name))
    model.graph.node.insert(
        index + 1,
        helper.make_node(
            "Slice",
            [
                node.output[0],
                "modelopt_slice_start",
                "modelopt_slice_end",
                "modelopt_slice_axis",
            ],
            [output],
            name="modelopt_projection_slice",
        ),
    )
    return remove_unused_nodes(model)


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
    recognition = align_recognizer_projection(recognition, 18432)
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
