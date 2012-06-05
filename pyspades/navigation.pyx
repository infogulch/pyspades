from pyspades.vxl cimport VXLData
from pyspades.common cimport Vertex3
from pyspades.common import sgn

cpdef is_location_local(a, b):
    x, y, z = a
    i, j, k = b
    size = HALF_GRID_SIZE - 2
    return (
        z - k < JUMP_HEIGHT and
        z - k >= -MAX_FALL and
        x >= i - size and x < i + size and 
        y >= j - size and y < j + size)

cdef class Navigation:
    def __init__(self, VXLData data):
        self.map = data.map
        self.graph = generate_navgraph(self.map)
    
    cpdef list find_path(self, int x1, int y1, int z1, int x2, int y2, int z2):
        cdef list path = []
        cdef list segment
        cdef Node* start = find_node(self.graph, x1, y1, z1)
        cdef Node* goal = find_node(self.graph, x2, y2, z2)
        cdef Node* prev
        cdef Node* node
        success = astar_compute(start, goal)
        if success:
            while goal.prev != NULL:
                prev = node = goal.prev
                segment = []
                while node != goal:
                    segment.append((node.x, node.y, node.z))
                    u = sgn(goal.x - node.x) + 1
                    v = sgn(goal.y - node.y) + 1
                    node = node.next[u][v]
                    assert(node != NULL)
                path.extend(reversed(segment))
                goal = prev
            path.append((start.x, start.y, start.z))
        return path
    
    cpdef list find_local_path(self, float x1, float y1, float z1,
        float x2, float y2, float z2):
        cdef float* points
        cdef list steps
        point_count = grid_bfs(self.map, &points, x1, y1, z1, x2, y2, z2)
        steps = [(points[i], points[i+1]) for i in xrange(0, point_count * 2, 2)]
        delete_points(&points)
        return steps
    
    cpdef get_node_count(self):
        return self.graph.total_nodes
    
    cpdef is_walkable(self, int x, int y, int z):
        return is_walkable(self.map, x, y, z)
    
    cpdef is_wall(self, int x, int y, int z):
        return is_wall(self.map, x, y, z)
    
    cpdef is_jumpable(self, int x, int y, int z):
        return is_jumpable(self.map, x, y, z)
    
    cpdef print_navgraph_csv(self):
        print_navgraph_csv(self.graph)