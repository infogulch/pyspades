#ifndef NAVIGATION_C_H
#define NAVIGATION_C_H

#include <cmath> // for HUGE_VAL
#include <vector>
#include <boost/unordered_map.hpp>
#include <boost/unordered_set.hpp>
#include "pairing_heap.h"

#define PLAYER_HEIGHT 3
#define JUMP_HEIGHT 2
#define MAX_FALL 8
#define HALF_GRID_SIZE 20
#define HEURISTIC_COST_SCALE 12.0f

typedef std::pair<int, int> direction;
typedef boost::unordered_set<direction> direction_set;

struct Node : pairing_node
{
    int const x, y, z;
    int const height;
    direction_set forced_neighbors[3][3];
    Node* next[3][3];
    
    float f, g, h;
    Node* prev;
    
    Node(int x, int y, int z, int height)
        : x(x), y(y), z(z), height(height)
    {
        for (int u = 0; u < 3; ++u)
            for (int v = 0; v < 3; ++v)
                next[u][v] = NULL;
    }
    
    bool operator< (Node const& b) const
    {
        return f < b.f;
    }
};

typedef boost::unordered_map<int, Node*> node_map;
typedef pairing_heap<Node> node_heap;

struct NavGraph
{
    node_map nodes;
    int total_nodes;
    
    NavGraph() : total_nodes(0) {}
};

struct LocalNode;
typedef std::vector<LocalNode*> lnode_vec;

struct LocalNode
{
    int const x_l, x_r, y, z;
    bool visited;
    lnode_vec next;
    //~ LocalNode* next[HALF_GRID_SIZE / 2];
    LocalNode* prev;
    
    LocalNode(int x_l, int x_r, int y, int z)
        : x_l(x_l), x_r(x_r), y(y), z(z), visited(false), prev(NULL) {}
};

struct LocalNodeCompare
{
    float const x1, y1, y2;
    float m_recp;
    
    LocalNodeCompare(float x1, float y1, float x2, float y2)
        : x1(x1), y1(y1), y2(y2)
    {
        m_recp = (y1 != y2) ? ((x2 - x1) / (y2 - y1)) : HUGE_VAL;
    }
    
    inline bool operator() (LocalNode const* a, LocalNode const* b) const
    {
        if (a->y == b->y && m_recp != HUGE_VAL) {
            float const x = (a->y - y1) * m_recp + x1;
            float const a_mid = a->x_l + (a->x_r - a->x_l) * 0.5f;
            float const b_mid = b->x_l + (b->x_r - b->x_l) * 0.5f;
            return abs(a_mid - x) < abs(b_mid - x);
        }
        return abs(a->y - y1) < abs(b->y - y1);
    }
};

enum NodeStatus {
    UNEXPLORED,
    OPEN,
    CLOSED
};

inline bool is_solid(MapData const* map, int x, int y, int z)
{
    return z < 0 || map->geometry[get_pos(x, y, z)];
}

inline bool is_wall(MapData const* map, int x, int y, int z)
{
    return (is_solid(map, x, y, z - 1) ||
        is_solid(map, x, y, z - 2) ||
        (is_solid(map, x, y, z) && is_solid(map, x, y, z - 3)));
}

inline bool is_jumpable(MapData const* map, int x, int y, int z)
{
    return (is_solid(map, x, y, z - 1) &&
        !is_solid(map, x, y, z - 2) &&
        !is_solid(map, x, y, z - 3) &&
        !is_solid(map, x, y, z - 4));
}

inline bool is_walkable(MapData const* map, int x, int y, int z)
{
    //~ static int const XY = MAP_X * MAP_Y;
    if (z > 62)
        return false;
    //~ int i = get_pos(x, y, z + 1);
    //~ for (int h = 0; i > 0 && h < PLAYER_HEIGHT + 1; i -= XY, ++h)
        //~ if (map->geometry[i] != (h == 0))
            //~ return false;
    if (!map->geometry[get_pos(x, y, z + 1)])
        return false;
    for (int h = 0; h < PLAYER_HEIGHT; ++h)
        if (map->geometry[get_pos(x, y, z - h)])
            return false;
    return true;
}

inline float tri_area_2(float const* a, float const* b, float const* c)
{
    float const abx = b[0] - a[0];
    float const aby = b[1] - a[1];
    float const acx = c[0] - a[0];
    float const acy = c[1] - a[1];
    return acx * aby - abx * acy;
}

inline float v_dist_sqr(float const* a, float const* b)
{
    float const x = a[0] - b[0];
    float const y = a[1] - b[1];
    return x*x + y*y;
}

inline bool v_equal(float const* a, float const* b)
{
    static float const eq = 0.001f * 0.001f;
    return v_dist_sqr(a, b) < eq;
}

inline void v_copy(float* dst, float const* src)
{
    dst[0] = src[0];
    dst[1] = src[1];
}

inline void delete_points(float** points)
{
    delete [] *points;
    *points = NULL;
}

/* function prototypes */

Node* find_node(NavGraph const* graph, int x, int y, int z);
NavGraph* generate_navgraph(MapData const* map);
void print_navgraph_csv(NavGraph* graph);
bool astar_compute(Node* start, Node* goal);
int grid_bfs(MapData const* map, float** points, float x1, float y1, float z1,
    float x2, float y2, float z2);

#endif /* NAVIGATION_C_H */