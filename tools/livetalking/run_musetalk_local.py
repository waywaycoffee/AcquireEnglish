"""Run MuseTalk 1.5 using the local Windows inference environment."""

import os
from importlib import import_module
from pathlib import Path
import runpy
import sys
from types import ModuleType


def register_pose_backbone() -> None:
    """Load only the MMDetection backbone used by MuseTalk's DWPose."""
    import mmdet
    from mmpose.registry import MODELS

    model_path = Path(mmdet.__file__).parent / "models"
    for name, path in (
        ("mmdet.models", model_path),
        ("mmdet.models.layers", model_path / "layers"),
        ("mmdet.models.backbones", model_path / "backbones"),
    ):
        package = ModuleType(name)
        package.__path__ = [str(path)]
        sys.modules[name] = package
    layers = sys.modules["mmdet.models.layers"]
    layers.CSPLayer = import_module("mmdet.models.layers.csp_layer").CSPLayer
    backbone = import_module("mmdet.models.backbones.cspnext").CSPNeXt
    MODELS.register_module(module=backbone)


def main() -> None:
    root = Path(__file__).resolve().parents[2] / "third_party" / "MuseTalk"
    os.chdir(root)
    sys.path.insert(0, str(root))

    # DWPose inference does not use the extended COCO keypoint evaluation APIs.
    # Use the Windows wheel for its standard COCO imports when xtcocotools is absent.
    try:
        import xtcocotools
    except ModuleNotFoundError:
        import pycocotools

        sys.modules["xtcocotools"] = pycocotools

    # MMCV Lite lacks compiled detection ops, which the CSPNeXt backbone never uses.
    register_pose_backbone()
    sys.argv[1:1] = [
        "--version", "v15",
        "--unet_config", "./models/musetalkV15/musetalk.json",
        "--unet_model_path", "./models/musetalkV15/unet.pth",
        "--use_float16",
        "--batch_size", "2",
    ]
    import numpy as np
    import torch
    from mmengine.logging import HistoryBuffer

    # The official DWPose checkpoint includes NumPy metadata.
    with torch.serialization.safe_globals([
        (np._core.multiarray._reconstruct, "numpy.core.multiarray._reconstruct"),
        (np._core.multiarray.scalar, "numpy.core.multiarray.scalar"),
        HistoryBuffer,
        np.ndarray,
        np.dtype,
        type(np.dtype("float32")),
        type(np.dtype("float64")),
        type(np.dtype("int64")),
        type(np.dtype("int32")),
        type(np.dtype("uint8")),
    ]):
        runpy.run_module("scripts.inference", run_name="__main__")


if __name__ == "__main__":
    main()
