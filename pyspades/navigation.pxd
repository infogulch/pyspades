cdef extern from "vxl_c.h":
    enum:
        MAP_X
        MAP_Y
        MAP_Z
    struct MapData:
        pass

cdef extern from "navigation_c.cpp":
    enum:
        HALF_GRID_SIZE
        JUMP_HEIGHT
        MAX_FALL
    struct NavGraph:
        int total_nodes
    struct Node:
        int x, y, z
        Node* next[3][3]
        Node* prev
    
    NavGraph* generate_navgraph(MapData* map)
    void print_navgraph_csv(NavGraph* graph)
    Node* find_node(NavGraph* graph, int x, int y, int z)
    bint astar_compute(Node* start, Node* goal)
    int grid_bfs(MapData* map, float** points, float x1, float y1, float z1,
        float x2, float y2, float z2)
    void delete_points(float** points)
    bint is_walkable(MapData* map, int x, int y, int z)
    bint is_wall(MapData* map, int x, int y, int z)
    bint is_jumpable(MapData* map, int x, int y, int z)

cdef class Navigation:
    cdef NavGraph* graph
    cdef MapData* map
    
    cpdef get_node_count(self)
    cpdef print_navgraph_csv(self)
    cpdef list find_path(self, int x1, int y1, int z1, int x2, int y2, int z2)
    cpdef list find_local_path(self, float x1, float y1, float z1, float x2,
        float y2, float z2)
    cpdef is_walkable(self, int x, int y, int z)
    cpdef is_wall(self, int x, int y, int z)
    cpdef is_jumpable(self, int x, int y, int z)