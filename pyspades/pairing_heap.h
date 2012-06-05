#ifndef PAIRING_HEAP_H
#define PAIRING_HEAP_H

#include <algorithm>

struct pairing_node
{
    pairing_node* left_child;
    pairing_node** prev_next;
    pairing_node* right_sibling;
};

template<typename T>
struct pairing_heap
{
    static T* downcast(pairing_node* p)
    {
        return static_cast<T*>(p);
    }
    
    static pairing_node* upcast(T* p)
    {
        return static_cast<pairing_node*>(p);
    }
    
    pairing_heap()
    : root(0)
    {
    }
    
    ~pairing_heap()
    {
        clear();
    }
    
    bool empty() const
    {
        return !root;
    }
    
    void insert(T* el_)
    {
        pairing_node* el = upcast(el_);
        el->left_child = 0;
        if (!root)
            root = el;
        else
            root = comparison_link(root, el);
    }
    
    void decreased_key(T* el_)
    {
        pairing_node* el = upcast(el_);
        if (el != root) {
            unlink_subtree(el);
            root = comparison_link(root, el);
        }
    }
    
    T* unlink_min()
    {
        pairing_node* ret = root;
        pairing_node* left_child = ret->left_child;
        if (left_child)
            root = combine_siblings(left_child);
        else
            root = 0;
        return downcast(ret);
    }
    
    void clear()
    {
        if (!root)
            return;
        delete_subtree(root);
        unlink_all();
    }
    
    void unlink_all()
    {
        root = 0;
    }
    
    T& min()
    {
        return *downcast(root);
    }
    
    std::size_t size() const
    {
        if (!root)
            return 0;
        return 1 + subtree_size(root->left_child);
    }
    
private:
    std::size_t subtree_size(pairing_node* el) const
    {
        if (!el)
            return 0;
        return 1 + subtree_size(el->left_child) + subtree_size(el->right_sibling);
    }
    
    void unlink_subtree(pairing_node* el)
    {
        pairing_node** prev_next = el->prev_next;
        pairing_node* right_sibling = el->right_sibling;
        if (right_sibling)
            right_sibling->prev_next = prev_next;
        *prev_next = right_sibling;
    }
    
    pairing_node* comparison_link(pairing_node* a, pairing_node* b)
    {
        if ((*downcast(a)) < (*downcast(b))) {
            b->prev_next = &a->left_child;
            pairing_node* child = a->left_child;
            b->right_sibling = child;
            if (child)
                child->prev_next = &b->right_sibling;
            a->left_child = b;
            return a;
        } else {
            a->prev_next = &b->left_child;
            pairing_node* child = b->left_child;
            a->right_sibling = child;
            if (child)
                child->prev_next = &a->right_sibling;
            b->left_child = a;
            return b;
        }
    }
    
    pairing_node* combine_siblings(pairing_node* el)
    {
        pairing_node* first = el;
        pairing_node* second = first->right_sibling;
        if (!second)
            return first;
        pairing_node* next = second->right_sibling;
        pairing_node* stack = comparison_link(first, second);
        if (!next)
            return stack;
        
        stack->right_sibling = 0;
        do {
            first = next;
            second = next->right_sibling;
            if (!second) {
                first->right_sibling = stack;
                stack = first;
                break;
            }
            next = second->right_sibling;
            pairing_node* tree = comparison_link(first, second);
            tree->right_sibling = stack;
            stack = tree;
        } while (next);
        
        first = stack;
        second = stack->right_sibling;
        do {
            pairing_node* next = second->right_sibling;
            first = comparison_link(first, second);
            second = next;
        } while (second);
        
        return first;
    }
    
    void delete_subtree(pairing_node* el)
    {
        pairing_node* child = el->left_child;
        while (child) {
            pairing_node* next = child->right_sibling;
            delete_subtree(child);
            child = next;
        }
    }
    
    pairing_node* root;
};

#endif /* PAIRING_HEAP_H */