use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, ItemFn};

#[proc_macro_attribute]
pub fn entry(_args: TokenStream, input: TokenStream) -> TokenStream {
    let f = parse_macro_input!(input as ItemFn);

    let stmts = f.block.stmts;
    let ret = f.sig.output;

    quote! {
        #[export_name = "main"]
        fn __rt__main() -> i32 {
            use rt::Termination;

            fn __og() #ret {
                #(#stmts)*
            }

            __og().exit()
        }
    }
    .into()
}
