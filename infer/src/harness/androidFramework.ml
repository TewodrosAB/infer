(*
 * Copyright (c) 2013 - present Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *)

open! Utils

module L = Logging
module F = Format
module TypSet = Typ.StructSet

(** Android lifecycle types and their lifecycle methods that are called by the framework *)

let on_destroy = "onDestroy"
let on_destroy_view = "onDestroyView"

(** return true if [pname] is a special lifecycle cleanup method *)
let is_destroy_method pname =
  match pname with
  | Procname.Java pname_java ->
      let method_name = Procname.java_get_method pname_java in
      string_equal method_name on_destroy || string_equal method_name on_destroy_view
  | _ ->
      false

let android_lifecycles =
  let android_content = "android.content" in
  let android_app = "android.app" in
  let fragment_lifecycle =
    ["onInflate"; "onAttach"; "onCreate"; "onCreateView"; "onViewCreated"; "onActivityCreated";
     "onViewStateRestored"; "onStart"; "onResume"; "onPause"; "onSaveInstanceState"; "onStop";
     on_destroy_view; on_destroy; "onDetach"] in
  [ (android_content,
     "ContentProvider",
     ["onCreate"]);
    (android_app,
     "Activity",
     ["onCreate"; "onStart"; "onRestoreInstanceState"; "onPostCreate"; "onResume"; "onPostResume";
      "onCreateDescription"; "onSaveInstanceState"; "onPause"; "onStop"; on_destroy]);
    (android_app,
     "Service",
     ["onCreate"; "onStart"; "onStartCommand"; "onBind"; "onUnbind"; on_destroy]);
    (android_content,
     "BroadcastReceiever",
     ["onReceive"]);
    (android_app,
     "Fragment",
     fragment_lifecycle);
    (* this is the pre-Android 3.0 Fragment type (can also be used post-3.0) *)
    ("android.support.v4.app",
     "Fragment",
     fragment_lifecycle);
  ]

let is_subtype_package_class tenv struct_typ package classname =
  let classname = Mangled.from_package_class package classname in
  match Tenv.lookup tenv (Typename.TN_csu (Csu.Class Csu.Java, classname)) with
  | Some found_struct_typ -> PatternMatch.is_subtype tenv struct_typ found_struct_typ
  | _ -> false

let is_context tenv typ =
  is_subtype_package_class tenv typ "android.content" "Context"

let is_application tenv typ =
  is_subtype_package_class tenv typ "android.app" "Application"

let is_activity tenv typ =
  is_subtype_package_class tenv typ "android.app" "Activity"

let is_view tenv typ =
  is_subtype_package_class tenv typ "android.view" "View"

let is_fragment tenv typ =
  is_subtype_package_class tenv typ "android.app" "Fragment" ||
  is_subtype_package_class tenv typ "android.support.v4.app" "Fragment"

(** return true if [class_name] is the name of a class that belong to the Android framework *)
let is_android_lib_class class_name =
  let class_str = Typename.name class_name in
  string_is_prefix "android" class_str || string_is_prefix "com.android" class_str

(** given an Android framework type mangled string [lifecycle_typ] (e.g., android.app.Activity) and
    a list of method names [lifecycle_procs_strs], get the appropriate typ and procnames *)
let get_lifecycle_for_framework_typ_opt tenv lifecycle_typ lifecycle_proc_strs =
  match Tenv.lookup tenv (Typename.TN_csu (Csu.Class Csu.Java, lifecycle_typ)) with
  | Some ({ Typ.csu = Csu.Class _; struct_name = Some _; def_methods } as lifecycle_typ) ->
      (* TODO (t4645631): collect the procedures for which is_java is returning false *)
      let lookup_proc lifecycle_proc =
        IList.find (fun decl_proc ->
            match decl_proc with
            | Procname.Java decl_proc_java ->
                lifecycle_proc = Procname.java_get_method decl_proc_java
            | _ ->
                false
          ) def_methods in
      (* convert each of the framework lifecycle proc strings to a lifecycle method procname *)
      let lifecycle_procs =
        IList.fold_left (fun lifecycle_procs lifecycle_proc_str ->
            try (lookup_proc lifecycle_proc_str) :: lifecycle_procs
            with Not_found -> lifecycle_procs)
          [] lifecycle_proc_strs in
      Some (lifecycle_typ, lifecycle_procs)
  | _ -> None

(** return the complete list of (package, lifecycle_classname, lifecycle_methods) trios *)
let get_lifecycles = android_lifecycles

let non_stub_android_jar () =
  let root_dir = Filename.dirname (Filename.dirname Sys.executable_name) in
  IList.fold_left Filename.concat root_dir ["lib"; "java"; "android"; "android-19.jar"]
