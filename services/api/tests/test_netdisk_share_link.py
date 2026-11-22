import pytest

from app.services.netdisk_share_link import netdisk_share_provider


@pytest.mark.parametrize("url,provider", [
    ("https://pan.baidu.com/s/abc", "baidu"),
    ("https://pan.quark.cn/s/abc", "quark"),
    ("https://www.alipan.com/s/abc", "aliyun"),
    ("https://115.com/s/abc", "pan115"),
])
def test_provider_detection(url, provider):
    assert netdisk_share_provider(url) == provider


@pytest.mark.parametrize("url", [
    "http://pan.baidu.com/s/abc",
    "https://pan.baidu.com.evil.example/s/abc",
    "https://user@pan.quark.cn/s/abc",
    "https://pan.quark.cn/",
])
def test_rejects_untrusted_links(url):
    assert netdisk_share_provider(url) is None
