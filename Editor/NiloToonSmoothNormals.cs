using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public static class NiloToonSmoothNormals
{
    [MenuItem("Tools/Nilo Toon/Bake Smooth Outline Normals")]
    static void BakeSelection()
    {
        var visited = new HashSet<Component>();
        foreach (GameObject selected in Selection.gameObjects)
        {
            foreach (MeshFilter filter in selected.GetComponentsInChildren<MeshFilter>(true))
                if (visited.Add(filter) && filter.sharedMesh)
                    SaveClone(filter, filter.sharedMesh, mesh => filter.sharedMesh = mesh);
            foreach (SkinnedMeshRenderer renderer in selected.GetComponentsInChildren<SkinnedMeshRenderer>(true))
                if (visited.Add(renderer) && renderer.sharedMesh)
                    SaveClone(renderer, renderer.sharedMesh, mesh => renderer.sharedMesh = mesh);
        }
    }

    [MenuItem("Tools/Nilo Toon/Bake Smooth Outline Normals", true)]
    static bool ValidateSelection() => Selection.gameObjects.Length > 0;

    static void SaveClone(Component target, Mesh source, Action<Mesh> assign)
    {
        if (!source.isReadable)
        {
            Debug.LogError($"Enable Read/Write on {source.name} before baking outline normals.", target);
            return;
        }
        if (source.HasVertexAttribute(VertexAttribute.TexCoord3) &&
            !EditorUtility.DisplayDialog("UV4 is already in use",
                $"The new copy of {source.name} will replace UV4 with outline normals. The source asset stays unchanged.",
                "Bake copy", "Skip"))
            return;

        string path = EditorUtility.SaveFilePanelInProject("Save smooth outline mesh",
            source.name + "_SmoothOutline", "asset", "Choose a new mesh asset. The imported source stays unchanged.");
        if (string.IsNullOrEmpty(path))
            return;
        if (AssetDatabase.LoadMainAssetAtPath(path))
        {
            Debug.LogError("Choose a new asset path; the outline baker does not overwrite existing assets.", target);
            return;
        }

        Mesh copy = UnityEngine.Object.Instantiate(source);
        copy.name = source.name + "_SmoothOutline";
        try
        {
            Bake(copy);
            AssetDatabase.CreateAsset(copy, path);
            Undo.RecordObject(target, "Assign smooth outline mesh");
            assign(copy);
            PrefabUtility.RecordPrefabInstancePropertyModifications(target);
            EditorUtility.SetDirty(target);
            AssetDatabase.SaveAssets();
            Debug.Log($"Saved {path}. Enable Use Smooth Outline Normal on its toon materials. UV4 is reserved for this data.", target);
        }
        catch (Exception error)
        {
            if (!AssetDatabase.Contains(copy))
                UnityEngine.Object.DestroyImmediate(copy);
            Debug.LogException(error, target);
        }
    }

    public static void Bake(Mesh mesh)
    {
        Vector3[] positions = mesh.vertices;
        Vector3[] normals = mesh.normals;
        if (normals.Length != positions.Length)
            throw new InvalidOperationException("The mesh must have valid original normals; import them before baking.");
        if (!mesh.HasVertexAttribute(VertexAttribute.Tangent))
        {
            if (!mesh.HasVertexAttribute(VertexAttribute.TexCoord0))
                throw new InvalidOperationException("Missing tangents and UV0; import tangents or UV0 before baking.");
            mesh.RecalculateTangents();
        }
        Vector4[] tangents = mesh.tangents;
        if (tangents.Length != positions.Length)
            throw new InvalidOperationException("The mesh must have a tangent for every vertex.");

        // shortcut: exact coincident positions share normals; near seams or incompatible skin weights require an artist-authored bake.
        var sums = new Dictionary<Vector3, Vector3>();
        for (int i = 0; i < positions.Length; ++i)
        {
            sums.TryGetValue(positions[i], out Vector3 sum);
            sums[positions[i]] = sum + normals[i];
        }

        var encoded = new List<Vector3>(positions.Length);
        for (int i = 0; i < positions.Length; ++i)
        {
            Vector3 normal = normals[i].normalized;
            Vector3 tangent = new Vector3(tangents[i].x, tangents[i].y, tangents[i].z);
            tangent = (tangent - normal * Vector3.Dot(normal, tangent)).normalized;
            if (normal.sqrMagnitude < 0.5f || tangent.sqrMagnitude < 0.5f || Mathf.Abs(tangents[i].w) < 0.5f)
                throw new InvalidOperationException($"Invalid normal/tangent basis at vertex {i}.");
            Vector3 bitangent = Vector3.Cross(normal, tangent) * Mathf.Sign(tangents[i].w);
            Vector3 smooth = sums[positions[i]].normalized;
            if (smooth.sqrMagnitude < 0.5f)
                smooth = normal;
            encoded.Add(new Vector3(Vector3.Dot(smooth, tangent), Vector3.Dot(smooth, bitangent), Vector3.Dot(smooth, normal)));
        }
        mesh.SetUVs(3, encoded);
    }
}
