"""Windows D3D11 syntax/entry-point check against official URP 17 headers.

Uses the Windows D3D compiler and Python standard library, no Unity install.
Downloads missing includes from Unity's 6000.0/staging branch into .validation/.
This checks HLSL, not ShaderLab import, C#, Render Graph, or GPU output.
"""
import ctypes as c
import os
from pathlib import Path
import re
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.validation' / 'urp17'
REMOTE = 'https://raw.githubusercontent.com/Unity-Technologies/Graphics/6000.0/staging/'


def run():
    if os.name != 'nt':
        raise SystemExit('This check requires Windows d3dcompiler_47.dll.')
    compiler = c.WinDLL('d3dcompiler_47.dll')
    hresult = c.c_long
    open_type = c.WINFUNCTYPE(hresult, c.c_void_p, c.c_int, c.c_char_p,
                             c.c_void_p, c.POINTER(c.c_void_p), c.POINTER(c.c_uint))
    close_type = c.WINFUNCTYPE(hresult, c.c_void_p, c.c_void_p)
    buffers = {}
    paths = {}
    include_errors = []

    @open_type
    def open_include(this, kind, name, parent, output, size):
        try:
            name = name.decode('utf8')
            if name.startswith('Packages/'):
                path = CACHE / name
            else:
                path = paths.get(parent, ROOT / 'entry.hlsl').parent / name
            path = path.resolve()
            if not path.is_relative_to(ROOT):
                raise ValueError('Include escaped workspace: ' + str(path))
            if not path.exists():
                relative = path.relative_to(CACHE).as_posix()
                if not relative.startswith('Packages/'):
                    raise ValueError('Missing local include: ' + str(path))
                with urllib.request.urlopen(REMOTE + relative, timeout=30) as response:
                    source = response.read()
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(source)
            source = path.read_bytes()
            # Unity normally preprocesses this unused instrumentation macro before FXC.
            source = source.replace(b'#define PopMarker()', b'// Empty marker macro omitted for standalone FXC')
            buffer = c.create_string_buffer(source)
            address = c.addressof(buffer)
            buffers[address] = buffer
            paths[address] = path
            output[0] = address
            size[0] = len(source)
            return 0
        except Exception as error:
            include_errors.append(str(error))
            return -2147467259

    @close_type
    def close_include(this, data):
        buffers.pop(data, None)
        paths.pop(data, None)
        return 0

    class IncludeVTable(c.Structure):
        _fields_ = [('open', open_type), ('close', close_type)]

    class Include(c.Structure):
        _fields_ = [('vtable', c.POINTER(IncludeVTable))]

    class Macro(c.Structure):
        _fields_ = [('name', c.c_char_p), ('value', c.c_char_p)]

    vtable = IncludeVTable(open_include, close_include)
    include = Include(c.pointer(vtable))
    compiler.D3DCompile.argtypes = [c.c_void_p, c.c_size_t, c.c_char_p, c.POINTER(Macro),
        c.c_void_p, c.c_char_p, c.c_char_p, c.c_uint, c.c_uint,
        c.POINTER(c.c_void_p), c.POINTER(c.c_void_p)]
    compiler.D3DCompile.restype = hresult

    def blob_text(blob):
        if not blob.value:
            return ''
        table = c.cast(blob, c.POINTER(c.POINTER(c.c_void_p))).contents
        pointer = c.WINFUNCTYPE(c.c_void_p, c.c_void_p)(table[3])(blob)
        size = c.WINFUNCTYPE(c.c_size_t, c.c_void_p)(table[4])(blob)
        return c.string_at(pointer, size).decode('utf8', errors='replace')

    def release(blob):
        if blob.value:
            table = c.cast(blob, c.POINTER(c.POINTER(c.c_void_p))).contents
            c.WINFUNCTYPE(c.c_ulong, c.c_void_p)(table[2])(blob)

    source = b'#include "SimpleURPToonLitOutlineExample_Shared.hlsl"\n'
    post_shader = (ROOT / 'NiloToonPostProcess.shader').read_text(encoding='utf-8-sig')
    post_source = re.search(r'HLSLINCLUDE(.*?)ENDHLSL', post_shader, re.S).group(1).encode()
    base = {'SHADER_API_D3D11': '1', 'UNITY_COMPILER_HLSL': '1', 'SHADER_TARGET': '45',
            'UNITY_VERSION': '600000', 'UNITY_REVERSED_Z': '1',
            'UNITY_UNIFIED_SHADER_PRECISION_MODEL': '1'}
    variants = [
        ('vertex', 'VertexShaderWork', 'vs_5_0', {}),
        ('outline', 'VertexShaderWork', 'vs_5_0', {'ToonShaderIsOutline': '1'}),
        ('shadow', 'VertexShaderWork', 'vs_5_0', {'ToonShaderApplyShadowBiasFix': '1', '_CASTING_PUNCTUAL_LIGHT_SHADOW': '1'}),
        ('forward', 'ShadeFinalColor', 'ps_5_0', {}),
        ('forward-lit', 'ShadeFinalColor', 'ps_5_0', {'_MAIN_LIGHT_SHADOWS_CASCADE': '1', '_ADDITIONAL_LIGHTS': '1', '_ADDITIONAL_LIGHT_SHADOWS': '1', '_SHADOWS_SOFT': '1', '_UseAlphaClipping': '1'}),
        ('forward-plus', 'ShadeFinalColor', 'ps_5_0', {'_FORWARD_PLUS': '1', '_ADDITIONAL_LIGHTS': '1', '_UseAlphaClipping': '1'}),
        ('outline-fragment', 'ShadeFinalColor', 'ps_5_0', {'ToonShaderIsOutline': '1'}),
        ('extra-outline', 'ShadeFinalColor', 'ps_5_0', {'ToonShaderIsOutline': '1', 'ToonShaderIsExtraOutline': '1'}),
        ('depth', 'DepthOnlyFragment', 'ps_5_0', {'_UseAlphaClipping': '1'}),
        ('normals', 'DepthNormalsFragment', 'ps_5_0', {'_GBUFFER_NORMALS_OCT': '1', '_UseAlphaClipping': '1'}),
        ('hair', 'HairDepthFragment', 'ps_5_0', {}),
        ('eyes', 'EyeOverlayFragment', 'ps_5_0', {}),
        ('mask', 'CharacterMaskFragment', 'ps_5_0', {}),
        ('stereo-vertex', 'VertexShaderWork', 'vs_5_0', {'STEREO_INSTANCING_ON': '1'}),
        ('stereo-forward', 'ShadeFinalColor', 'ps_5_0', {'STEREO_INSTANCING_ON': '1'}),
        ('post-vertex', 'Vert', 'vs_5_0', {}),
        ('post-extract', 'ExtractBloom', 'ps_5_0', {}),
        ('post-blur', 'BlurBloom', 'ps_5_0', {}),
        ('post-composite', 'Composite', 'ps_5_0', {}),
    ]
    failed = 0
    for label, entry, target, additions in variants:
        definitions = dict(base, **additions)
        macros = (Macro * (len(definitions) + 1))(*[
            Macro(key.encode(), value.encode()) for key, value in definitions.items()])
        code, errors = c.c_void_p(), c.c_void_p()
        entry_source = post_source if label.startswith('post-') else source
        result = compiler.D3DCompile(entry_source, len(entry_source), b'entry.hlsl', macros, c.byref(include),
            entry.encode(), target.encode(), 1 << 11, 0, c.byref(code), c.byref(errors))
        diagnostic = blob_text(errors)
        release(errors)
        release(code)
        if result < 0:
            failed += 1
            print('FAIL', label, diagnostic, '\n'.join(include_errors), flush=True)
        else:
            print('PASS', label, flush=True)
        include_errors.clear()
    print(f'{len(variants) - failed}/{len(variants)} HLSL entry/variant checks passed.')
    return bool(failed)


if __name__ == '__main__':
    sys.exit(run())
