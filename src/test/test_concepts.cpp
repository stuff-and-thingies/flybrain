#include <concepts>
#include <string_view>

#include <iostream>

template <typename T>
concept HasName = requires {
    { T::name } -> std::convertible_to<std::string_view>;
};

template<typename Derived>
struct Nameable {
    Nameable() {
        static_assert(HasName<Derived>, "Derived class must define `static constexpr std::string_view name`");
    }
};

struct Foo : Nameable<Foo> {
    static constexpr std::string_view name = "asdf1";
};

struct Foo2 : Nameable<Foo2> {
    static constexpr std::string_view name = "asdf3";
};

struct Bar : Nameable<Bar> {
    static constexpr std::string_view name = "asdf";
};

// value of how many matches T0 has with any of the Ts
template <class T0, class... Ts>
inline constexpr std::size_t T0_name_equality_count = (static_cast<unsigned int>(std::string_view(T0::name) == std::string_view(Ts::name)) + ...);

// iterate through all Ts, assert that each one only has one match for the name (to itself)
template <class... Ts>
inline constexpr bool has_unique_names = ((T0_name_equality_count<Ts, Ts...> == 1) && ...);



int main() {
    Foo foo;
    Foo2 foo2;
    Bar bar2;
    auto test = has_unique_names<Foo, Foo2, Bar>;

    // CommsBus bus(foo, foo2, bar2);

    std::cout << test <<std::endl;
}