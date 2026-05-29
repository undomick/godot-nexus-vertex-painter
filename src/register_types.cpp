#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "vertex_painter_constants.h"
#include "vertex_painter_core.h"

#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void initialize_nexus_vertex_painter_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(VertexPainterCore);
}

void uninitialize_nexus_vertex_painter_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {

GDExtensionBool GDE_EXPORT nexus_vertex_painter_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_nexus_vertex_painter_module);
	init_obj.register_terminator(uninitialize_nexus_vertex_painter_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	const bool ok = init_obj.init();
	if (ok) {
		UtilityFunctions::print(
				String("Nexus Vertex Painter GDExtension v") + vertex_painter::kVersion + " ("
				+ vertex_painter::kAuthor + ")");
	}
	return ok;
}

}
