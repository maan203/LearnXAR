package com.example.learnxar_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.learnxar/ar_launcher"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "launchAR") {
                    try {
                        val flutterKey = call.argument<String>("moduleKey") ?: "stack"
                        val unityKey = mapToUnityKey(flutterKey)

                        if (unityKey == null) {
                            result.error(
                                "NO_AR_SCENE",
                                "No AR scene available for module: $flutterKey",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        val intent = Intent(
                            this,
                            Class.forName("com.unity3d.player.UnityPlayerActivity")
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        // Pass via intent extra — Unity reads this directly
                        intent.putExtra("moduleKey", unityKey)
                        startActivity(intent)

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LAUNCH_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun mapToUnityKey(flutterKey: String): String? {
        return when (flutterKey) {
            // Existing
            "stack"           -> "stack"
            "introduction"    -> "introduction"
            "linear_search"   -> "search_linear"
            "binary_search"   -> "search_binary"
            "bubble_sort"     -> "sort_bubble"
            "selection_sort"  -> "sort_selection"
            "insertion_sort"  -> "sort_insertion"
            "merge_sort"      -> "sort_merge"
            "quick_sort"      -> "sort_quick"

            // NEW: Queue
            "queue"           -> "queue"

            // NEW: Linked List
            "linked_list"            -> "linked_list"
            "singly_linked_list"     -> "singly_linked_list"
            "doubly_linked_list"     -> "doubly_linked_list"
            "circular_linked_list"   -> "circular_linked_list"

            // NEW: Arrays
            "arrays"                     -> "arrays"
            "1d_arrays"                  -> "1d_arrays"
            "2d_arrays"                  -> "2d_arrays"
            "multi-dimensional_arrays"   -> "multi_dimensional_arrays"

            // NEW: Trees
            "trees"               -> "trees"
            "binary_trees"        -> "binary_trees"
            "bst"                 -> "binary_search_tree"
            "avl_trees"           -> "avl_trees"

            else -> null
        }
    }
}