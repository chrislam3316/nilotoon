using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

public static class NiloToonDemo
{
    [MenuItem("Tools/Nilo Toon/Create Two Camera Demo")]
    public static void Create()
    {
        Shader shader = Shader.Find("SimpleURPToonLitExample(With Outline)");
        if (!shader) throw new System.InvalidOperationException("Import the toon shader first.");
        string folder = AssetDatabase.GenerateUniqueAssetPath("Assets/NiloToonDemo");
        AssetDatabase.CreateFolder("Assets", System.IO.Path.GetFileName(folder));
        Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Additive);
        var character = new GameObject("Character - adjust Perspective Correction");
        SceneManager.MoveGameObjectToScene(character, scene);
        var material = new Material(shader) { name = "Demo toon" };
        material.SetColor("_BaseColor", new Color(0.4f, 0.65f, 0.9f));
        material.SetFloat("_OutlineWidth", 2);
        material.SetFloat("_IndirectLightMultiplier", 0);
        AssetDatabase.CreateAsset(material, folder + "/DemoToon.mat");
        Part(character.transform, material, "Body", PrimitiveType.Cube, new Vector3(0, 0.9f, 0), new Vector3(0.65f, 0.9f, 0.4f));
        Part(character.transform, material, "Head", PrimitiveType.Sphere, new Vector3(0, 1.65f, 0), Vector3.one * 0.7f);
        Part(character.transform, material, "Nose (near feature)", PrimitiveType.Sphere, new Vector3(0, 1.65f, 0.4f), Vector3.one * 0.22f);
        Part(character.transform, material, "Left hand", PrimitiveType.Sphere, new Vector3(-0.65f, 1.05f, 0.5f), Vector3.one * 0.35f);
        Part(character.transform, material, "Right hand", PrimitiveType.Sphere, new Vector3(0.65f, 1.05f, 0.5f), Vector3.one * 0.35f);
        Part(character.transform, material, "Left leg", PrimitiveType.Cube, new Vector3(-0.2f, 0.25f, 0), new Vector3(0.25f, 0.5f, 0.3f));
        Part(character.transform, material, "Right leg", PrimitiveType.Cube, new Vector3(0.2f, 0.25f, 0), new Vector3(0.25f, 0.5f, 0.3f));
        var pivot = new GameObject("Shared projection pivot");
        pivot.transform.SetParent(character.transform);
        pivot.transform.localPosition = new Vector3(0, 1.2f, 0);
        var controller = character.AddComponent<NiloToonCharacter>();
        controller.pivot = pivot.transform;
        controller.perspectiveCorrection = 0.7f;
        controller.RefreshTargets();

        CameraView(scene, "Camera A front", new Vector3(0.25f, 1.3f, 2.2f), new Rect(0, 0, 0.5f, 1));
        CameraView(scene, "Camera B side", new Vector3(2.2f, 1.3f, 0.25f), new Rect(0.5f, 0, 0.5f, 1));
        var lightObject = new GameObject("Directional light");
        SceneManager.MoveGameObjectToScene(lightObject, scene);
        var light = lightObject.AddComponent<Light>();
        light.type = LightType.Directional;
        light.intensity = 1;
        lightObject.transform.rotation = Quaternion.Euler(35, -145, 0);
        EditorSceneManager.SaveScene(scene, folder + "/TwoCameraDemo.unity");
        Selection.activeGameObject = character;
        Debug.Log("Two camera demo created in " + folder + ". Both cameras render the same mesh. " +
            "Compare correction 0 / 0.7 / 1 and move either camera. The original scene remains open.");
    }

    static void Part(Transform root, Material material, string name, PrimitiveType type, Vector3 position, Vector3 scale)
    {
        GameObject part = GameObject.CreatePrimitive(type);
        part.name = name;
        SceneManager.MoveGameObjectToScene(part, root.gameObject.scene);
        part.transform.SetParent(root);
        part.transform.localPosition = position;
        part.transform.localScale = scale;
        part.GetComponent<Renderer>().sharedMaterial = material;
    }

    static void CameraView(Scene scene, string name, Vector3 position, Rect viewport)
    {
        var go = new GameObject(name);
        SceneManager.MoveGameObjectToScene(go, scene);
        var camera = go.AddComponent<Camera>();
        camera.scene = scene;
        camera.rect = viewport;
        camera.fieldOfView = 75;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(0.08f, 0.1f, 0.14f);
        go.transform.position = position;
        go.transform.LookAt(new Vector3(0, 1.1f, 0));
    }
}
