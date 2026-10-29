using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

// Run after importing into Unity 6; does not require the Unity Test Framework package.
public static class NiloToonSelfCheck
{
    [MenuItem("Tools/Nilo Toon/Run Self Checks")]
    public static void Run()
    {
        Shader shader = Shader.Find("SimpleURPToonLitExample(With Outline)");
        Require(shader != null, "Character shader was not imported.");
        Require(!ShaderUtil.ShaderHasError(shader), "Character shader has compiler errors; inspect its Inspector.");
        Shader post = Shader.Find("Hidden/NiloToon/CharacterPostProcess");
        Require(post != null && !ShaderUtil.ShaderHasError(post), "Post shader is missing or has compiler errors.");
        var material = new Material(shader);
        try
        {
            foreach (string pass in new[] { "ForwardLit", "Outline", "ShadowCaster", "DepthOnly",
                "DepthNormalsOnly", "HairDepth", "EyeOverlay", "CharacterMask", "ExtraOutline" })
                Require(material.FindPass(pass) >= 0, "Missing shader pass: " + pass);
            CheckSmoothNormals();
            CheckCharacterOverrides(material);
        }
        finally { UnityEngine.Object.DestroyImmediate(material); }
        Debug.Log("Nilo Toon: shader import, pass presence, smooth normals and character lifecycle checks passed. " +
            "This does not exercise every GPU variant; use the two-camera demo for rendering checks.");
    }

    static void CheckSmoothNormals()
    {
        var mesh = new Mesh();
        try
        {
            mesh.vertices = new[] { Vector3.zero, Vector3.zero };
            mesh.normals = new[] { Vector3.forward, Vector3.up };
            mesh.tangents = new[] { new Vector4(1, 0, 0, 1), new Vector4(1, 0, 0, 1) };
            NiloToonSmoothNormals.Bake(mesh);
            var encoded = new List<Vector3>();
            mesh.GetUVs(3, encoded);
            Require(encoded.Count == 2, "UV4 bake did not cover every vertex.");
            var expected = (Vector3.forward + Vector3.up).normalized;
            Vector3 reconstructed0 = Vector3.right * encoded[0].x + Vector3.up * encoded[0].y + Vector3.forward * encoded[0].z;
            Vector3 reconstructed1 = Vector3.right * encoded[1].x - Vector3.forward * encoded[1].y + Vector3.up * encoded[1].z;
            Require(Vector3.Distance(expected, reconstructed0) < 0.0001f &&
                Vector3.Distance(expected, reconstructed1) < 0.0001f, "Tangent-space outline normals do not reconstruct.");
            Require(mesh.normals[0] == Vector3.forward && mesh.normals[1] == Vector3.up, "Bake changed lighting normals.");
        }
        finally { UnityEngine.Object.DestroyImmediate(mesh); }
    }

    static void CheckCharacterOverrides(Material material)
    {
        var root = new GameObject("Nilo self check") { hideFlags = HideFlags.HideAndDontSave };
        root.SetActive(false);
        try
        {
            GameObject first = GameObject.CreatePrimitive(PrimitiveType.Cube);
            GameObject second = GameObject.CreatePrimitive(PrimitiveType.Cube);
            first.transform.SetParent(root.transform);
            second.transform.SetParent(root.transform);
            Renderer a = first.GetComponent<Renderer>(), b = second.GetComponent<Renderer>();
            a.sharedMaterial = b.sharedMaterial = material;
            Bounds originalBounds = a.localBounds;
            var block = new MaterialPropertyBlock();
            block.SetFloat("_DirectLightMultiplier", 0.7f);
            a.SetPropertyBlock(block, 0);
            var character = root.AddComponent<NiloToonCharacter>();
            character.perspectiveCorrection = 0.75f;
            root.transform.position = new Vector3(3, 1, 2);
            root.SetActive(true);
            a.GetPropertyBlock(block, 0);
            float id = block.GetFloat("_CharacterId");
            Require(id > 0 && Mathf.Approximately(block.GetFloat("_PerspectiveCorrection"), 0.75f), "Character properties were not applied.");
            Require(Vector3.Distance(block.GetVector("_CharacterPivotWS"), root.transform.position) < 0.0001f, "Shared pivot is wrong.");
            Require(Mathf.Approximately(block.GetFloat("_DirectLightMultiplier"), 0.7f), "Existing override was lost.");
            b.GetPropertyBlock(block, 0);
            Require(block.GetFloat("_CharacterId") == id, "Mesh parts have different character IDs.");
            character.enabled = false;
            a.GetPropertyBlock(block, 0);
            Require(!block.HasFloat("_PerspectiveCorrection") && Mathf.Approximately(block.GetFloat("_DirectLightMultiplier"), 0.7f), "Disable failed to restore the original property block.");
            Require(a.localBounds == originalBounds, "Disable failed to restore bounds.");
        }
        finally { UnityEngine.Object.DestroyImmediate(root); }
    }

    static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
